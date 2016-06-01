//
//  ModelLoader.swift
//  bInTest
//
//  Created by Sergey Minakov on 31.05.16.
//  Copyright © 2016 Naithar. All rights reserved.
//

import UIKit

class ModelLoader {
    
    static let baseUrl = "https://api.flickr.com/services/rest/"
    static let baseParameters = "format=json&&api_key=\(ModelLoader.apiKey)&nojsoncallback=?"
    static let apiKey = "b49d87bfd659c5768ab0eafa74f2b6a5"
    
    static let photoSession = { () -> NSURLSession in
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        let queue = NSOperationQueue()
        queue.name = "photo"
        queue.maxConcurrentOperationCount = 5
        
        return NSURLSession(configuration: configuration,
                            delegate: nil,
                            delegateQueue: queue)
    }()
    
    static let locationSession = { () -> NSURLSession in
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        configuration.timeoutIntervalForRequest = 10
        return NSURLSession(configuration: configuration)
    }()
    
    
    static let imageSession = { () -> NSURLSession in
        let configuration = NSURLSessionConfiguration.defaultSessionConfiguration()
        return NSURLSession(configuration: configuration)
    }()
    
    static func photosUrl(lat lat: Double, lon: Double) -> NSURL? {
        return NSURL(string: "\(self.baseUrl)?\(self.baseParameters)" +
            "&method=flickr.photos.search&has_geo=true&" +
            "tags=cat&per_page=50" +
            "&lat=\(lat)&lon=\(lon)&radius=3")
    }
    
    static func locationUrl(id photoId: String) -> NSURL? {
        return NSURL(string: "\(self.baseUrl)?\(self.baseParameters)" +
            "&method=flickr.photos.geo.getLocation&" +
            "photo_id=\(photoId)")
    }
    
    static func imageUrl(item data: MapItem) -> NSURL? {
        return NSURL(string: "http://farm\(data.farmId).staticflickr.com/\(data.serverId)/\(data.photoId)_\(data.secret)_s.jpg")
    }
    
    static func requestPhotos(lat lat: Double, lon: Double, contains: (MapItem) -> (Bool), closure: (array: [MapItem]) -> ()) {
        guard let url = self.photosUrl(lat: lat, lon: lon) else {
            NSLog("Can't build photos request URL")
            return
        }
        
        let task = self.photoSession.dataTaskWithURL(url) { data, response, error in
            guard let data = data where error == nil else {
                NSLog("Can't handle photos response data with error: \(error)")
                return
            }
            
            do {
                let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: [])
                
                guard let json = parsedData as? [String : AnyObject],
                    let photos = json["photos"] as? [String : AnyObject],
                    let array = photos["photo"] as? [[String: AnyObject]] where array.count > 0 else { return }
                
                var resultArray = [MapItem]()
                
                NSLog("Started photos handling with count: \(array.count)")
                
                for item in array {
                    autoreleasepool {
                        guard let photoId = item["id"] as? String,
                            let serverId = item["server"] as? String,
                            let farmId = item["farm"] as? Int,
                            let secret = item["secret"] as? String else { return }
                        
                        var mapItem = MapItem(photoId: photoId,
                            serverId: serverId,
                            farmId: farmId,
                            secret: secret,
                            lat: -1,
                            lon: -1)
                        
                        guard !contains(mapItem) else { return }
                        
                        (mapItem.lat, mapItem.lon) = requestLocation(photo: photoId)
                        
                        guard mapItem.lat != -1 && mapItem.lon != -1 else { return }
                        
                        resultArray.append(mapItem)
                    }
                }
                
                closure(array: resultArray)
            } catch {
                NSLog("Error in photos request json parsing: \(error)")
            }
        }
        
        task.resume()
    }
    
    static func requestLocation(photo id: String) -> (lat: Double, lon: Double) {
        guard let url = self.locationUrl(id: id) else {
            NSLog("Can't build location request URL")
            return (lat: -1, lon: -1)
        }
        
        let (responseData, _, error) = self.locationSession.synchronousDataTaskWithURL(url)
        
        guard let data = responseData where error == nil else {
            NSLog("Can't handle location response data with error: \(error)")
            return (lat: -1, lon: -1)
        }
        
        do {
            let parsedData = try NSJSONSerialization.JSONObjectWithData(data, options: [])
            
            guard let json = parsedData as? [String : AnyObject],
                let photo = json["photo"] as? [String : AnyObject],
                let location = photo["location"] as? [String : AnyObject],
                let latString = location["latitude"] as? String,
                let lat = Double(latString),
                let lonString = location["longitude"] as? String,
                let lon = Double(lonString) else {
                    NSLog("Can't handle parsed location request json")
                    return (lat: -1, lon: -1)
            }
            
            return (lat: lat, lon: lon)
        } catch {
            NSLog("Error in location request json parsing: \(error)")
            return (lat: -1, lon: -1)
        }
    }
    
    static func requestImage(photo data: MapItem, closure: (UIImage?) -> ()) {
        let resultClosure = { (image: UIImage?) -> () in
            dispatch_async(dispatch_get_main_queue()) {
                closure(image)
            }
        }
        
        guard let url = self.imageUrl(item: data) else {
            resultClosure(nil)
            return
        }
        
        let task = self.imageSession.dataTaskWithURL(url) { data, _, error in
            guard let data = data where error == nil,
                let image = UIImage(data: data) else {
                    resultClosure(nil)
                    return
            }
            
            let size = CGSize(width: 50, height: 50)
            let resultImage = image.scaled(to: size).rounded(with: 15)
            resultClosure(resultImage)
        }
        
        task.resume()
    }
}