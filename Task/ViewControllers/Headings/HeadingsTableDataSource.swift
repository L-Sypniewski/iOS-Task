//
//  HeadingsTableDataSource.swift
//  Task
//
//  Created by Łukasz Sypniewski on 05/03/2018.
//  Copyright © 2018 Łukasz Sypniewski. All rights reserved.
//

import UIKit
import CoreData

protocol HeadingsTableDataSourceDelegate: AnyObject {
    func checkNetworkConnection() -> Bool
    func handleNoConnectionError(error: Error)
    func handleNoDataError(error: Error)
    func handleInvalidDataError(error: Error)
    func handleUnknownError(error: Error)
    func downloadImage(from url: URL?, callBack: @escaping (_ imageData: Data?) -> ())
    func downloadData(endpoint: ArticlesProvider.Endpoints, itemsCount: Int, queries: [URLQueryItem], apiKey: String,
                                  callBack: @escaping (_ articlesData: Articles?, _ response: URLResponse?, _ error: Error?) -> ())
}

class HeadingsTableDataSource: NSObject {
    
    // MARK: Properties
    let fetchedResultsController: NSFetchedResultsController<Article>
    let persistentContainer: NSPersistentContainer
    static let defaultImage: UIImage = #imageLiteral(resourceName: "newsImage")
    weak var delegate: HeadingsTableDataSourceDelegate?
    lazy var cachedImages:[UIImage?] = [UIImage?]()
    
    // MARK: Initializers
    init(fetchedResultsController: NSFetchedResultsController<Article>, persistentContainer: NSPersistentContainer) {
        self.fetchedResultsController = fetchedResultsController
        self.persistentContainer = persistentContainer
    }
    
    // MARK: Configuring cell
    func configure(_ cell: HeadingsTableViewCell, at indexPath: IndexPath) {
        let index = indexPath
        let article = fetchedResultsController.object(at: indexPath)
        
        cell.title = article.title
        cell.source = article.sourceName
        
        if let articleImage = article.image {
            if let cachedImage = cachedImages[indexPath.row] {
                cell.newsImage = cachedImage
            } else {
                cell.newsImage = UIImage(data: articleImage) ?? HeadingsTableDataSource.defaultImage
            }
        } else {
            cell.newsImage = HeadingsTableDataSource.defaultImage
        }
        
        guard cachedImages.count > 0 else { return }
        guard cachedImages[indexPath.row] == nil else { return }
        delegate?.downloadImage(from: article.urlToImage) { data in
            guard let data = data else { return }
            guard let image = UIImage(data: data) else { return }
            DispatchQueue.main.async {
                guard index == indexPath else { return }
                cell.newsImage = image
                self.cachedImages[index.row] = image
                article.image = data
            }
        }
    }
    
    // MARK: Fetching data
    func downloadData(settings: QuerySettings) {
        delegate?.downloadData(endpoint: settings.endpoint!, itemsCount: settings.itemsCount!, queries: settings.queries!, apiKey: settings.apiKey!)
        { data, response, error in
            self.delegate?.checkNetworkConnection()
            if let error = error {
                if error.localizedDescription == "The Internet connection appears to be offline." {
                    self.delegate?.handleNoConnectionError(error: error)
                    return
                } else if data == nil {
                    if error.localizedDescription == "The data couldn’t be read because it isn’t in the correct format." {
                        self.delegate?.handleInvalidDataError(error: error)
                        return
                    } else {
                        self.delegate?.handleNoDataError(error: error)
                        return
                    }
                } else {
                    self.delegate?.handleUnknownError(error: error)
                    return
                }
            }
            self.cachedImages = [UIImage?]()
            self.cachedImages = Array(repeating: nil, count: data!.articles.count)
            for i in 0..<data!.articles.count {
                var article = data!.articles[i]
                if let url = article.url {
                    var urlComponents = URLComponents(url: url, resolvingAgainstBaseURL: false)
                    urlComponents!.scheme = "http"
                    article.url = urlComponents!.url
                }
                if let urlToImage = article.urlToImage {
                    var urlComponents = URLComponents(url: urlToImage, resolvingAgainstBaseURL: false)
                    urlComponents!.scheme = "http"
                    article.urlToImage = urlComponents!.url
                }
                DataModel.addArticle(article, context: self.persistentContainer.viewContext)
            }
            DataModel.SaveToPeristent(persistentContainer: self.persistentContainer)
        }
    }
}

// MARK: UITableViewDataSource
extension HeadingsTableDataSource : UITableViewDataSource {
    func numberOfSections(in tableView: UITableView) -> Int {
        guard let sections = self.fetchedResultsController.sections else { return 0 }
        return sections.count
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        guard let sectionInfo = self.fetchedResultsController.sections?[section] else { fatalError("Unexpected Section") }
        return sectionInfo.numberOfObjects
    }
    
    func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        guard let sectionInfo = self.fetchedResultsController.sections?[section] else { fatalError("Unexpected Section") }
        return sectionInfo.name
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        guard let cell = tableView.dequeueReusableCell(withIdentifier: "ArticleHeadingCell", for: indexPath) as? HeadingsTableViewCell else {
            fatalError("The dequeued cell is not an instance of ArticleHeadingTableViewCell")
        }
        let colorFirst = UIColor(red: 158.0/255.0, green: 184.0/255.0, blue: 226.0/255.0, alpha: 1.0)
        let colorSecond = UIColor(red: 184.0/255.0, green: 242.0/255.0, blue: 155.0/255.0, alpha: 1.0)
        cell.backgroundColor = indexPath.row % 2 == 0 ? colorFirst : colorSecond
        configure(cell, at: indexPath)
        return cell
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let article = self.fetchedResultsController.object(at: indexPath)
            article.managedObjectContext?.delete(article)
        }
    }
}