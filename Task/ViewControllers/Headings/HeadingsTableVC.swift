//
//  ArticleHeadingTableVC.swift
//  Task
//
//  Created by Łukasz Sypniewski on 14/02/2018.
//  Copyright © 2018 Łukasz Sypniewski. All rights reserved.
//

import UIKit
import CoreData

class HeadingsTableVC: UIViewController {
    
    // MARK: Outlets
    @IBOutlet weak var tableView: UITableView!
    
    // MARK: Properties
    let defaultImage: UIImage = #imageLiteral(resourceName: "newsImage")
    let persistentContainer = NSPersistentContainer(name: "Articles")
    let articleFerchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "Article")
    lazy var cachedImages:[UIImage?] = Array(repeating: nil, count: self.tableView.numberOfRows(inSection: 0))
    var isOnline = false {
        didSet {
            let title = isOnline ? "Breaking news" : "Breaking news (offline mode)"
            self.navigationItem.title = title
        }
    }
    private lazy var fetchedResultsController: NSFetchedResultsController<Article> = {
        // Create Fetch Request
        let fetchRequest: NSFetchRequest<Article> = Article.fetchRequest()
        
        // Configure Fetch Request
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: #keyPath(Article.sourceName), ascending: true)]
        
        // Create Fetched Results Controller
        let fetchedResultsController = NSFetchedResultsController(fetchRequest: fetchRequest, managedObjectContext: self.persistentContainer.viewContext,
                                                                  sectionNameKeyPath: nil, cacheName: nil)
        
        // Configure Fetched Results Controller
        fetchedResultsController.delegate = self
        
        return fetchedResultsController
    }()
    
    // MARK: Actions
    @IBAction func refreshButton(_ sender: Any?) {
        if checkNetworkConnection() {
            DataModel.deleteArticlesFromMemory(fetchedResultsController: fetchedResultsController)
            self.downloadData(settings: SettingsManager.loadAppSettings())
        }
    }
    
    @IBAction func unwindToArticleList(sender: UIStoryboardSegue) {
        if let sourceViewController = sender.source as? SettingsVC {
            SettingsManager.saveAppSettings(settings: sourceViewController.settings)
            refreshButton(self)
        }
    }
    
    // MARK: - View Methods
    override func viewDidLoad() {
        super.viewDidLoad()
        tableView.delegate = self
        tableView.dataSource = self
        DataModel.LoadPersistentStore(persistentContainer: persistentContainer, fetchedResultsController: fetchedResultsController)
        if checkNetworkConnection(){
            DataModel.deleteArticlesFromPersistentStorage(persistentContainer: persistentContainer, fetchRequest: articleFerchRequest,
                                                          tableView: self.tableView, fetchedResultsController: fetchedResultsController)
        }
        self.updateView()
        self.downloadData(settings: SettingsManager.loadAppSettings())
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if segue.identifier == "showDetailsSegue" {
            let article = fetchedResultsController.object(at: tableView.indexPathForSelectedRow!)
            let vc = segue.destination as! DetailsVC
            guard sender as? HeadingsTableViewCell != nil else { return }
            if let data = article.image
            {
                vc.image = UIImage(data: data)
            } else {
                vc.image = defaultImage
            }
            vc.defaultImage = defaultImage
            vc.article = article
        }
        if segue.identifier == "showSettingsSegue" {
            let navigationVC = segue.destination as! UINavigationController
            let settingsVC = navigationVC.viewControllers.first as! SettingsVC
            guard sender as? UIBarButtonItem != nil else { return }
            settingsVC.settings = SettingsManager.loadAppSettings()
        }
    }
    
    private func updateView() {
        var hasArticles = false
        if let articles = fetchedResultsController.fetchedObjects {
            hasArticles = articles.count > 0
        }
        tableView.isHidden = !hasArticles
    }
    
    func configure(_ cell: HeadingsTableViewCell, at indexPath: IndexPath) {
        let index = indexPath
        let article = fetchedResultsController.object(at: indexPath)
        
        cell.title = article.title
        cell.source = article.sourceName
        
        if let articleImage = article.image {
            if let cachedImage = cachedImages[indexPath.row] {
                cell.newsImage = cachedImage
            } else {
                cell.newsImage = UIImage(data: articleImage) ?? defaultImage
            }
        } else {
            cell.newsImage = defaultImage
        }
        
        guard cachedImages[indexPath.row] == nil else { return }
        ArticlesProvider.downloadImage(from: article.urlToImage) { data in
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
    
    // MARK: - Fetching data
    func downloadData(settings: QuerySettings) {
        ArticlesProvider.downloadData(endpoint: settings.endpoint!, itemsCount: settings.itemsCount!, queries: settings.queries!, apiKey: settings.apiKey!)
        { data, response, error in
            self.checkNetworkConnection()
            if let error = error {
                if error.localizedDescription == "The Internet connection appears to be offline." {
                    self.showNoConnectionAlert()
                    return
                } else if data == nil {
                    if error.localizedDescription == "The data couldn’t be read because it isn’t in the correct format." {
                        self.showInvalidDataFormat()
                        return
                    } else {
                        self.showNoDataAlert()
                        return
                    }
                } else {
                    self.showAlert(title: "Unknown error", message: "Error message: \(error.localizedDescription)", buttonText: "OK")
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
            DispatchQueue.main.async {
                self.tableView.reloadData()
            }
        }
    }
    
    // MARK: - Networking
    func checkNetworkConnection() -> Bool {
        isOnline = ArticlesProvider.connectedToNetwork()
        return isOnline
    }
    
    // MARK: - Displaying alerts
    func showAlert(title: String, message: String, buttonText: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: NSLocalizedString(buttonText, comment: "Default action"), style: .`default`, handler: nil))
        self.present(alert, animated: true, completion: nil)
    }
    
    func showNoConnectionAlert() {
        showAlert(title: "No internet connection", message: "There is no internet connection, data cannot be downloaded now.", buttonText: "OK")
    }
    
    func showNoDataAlert() {
        showAlert(title: "No data has been downloaded", message: "No data has been downloaded. Check your internet connection and connection parameters!", buttonText: "OK")
    }
    
    func showInvalidDataFormat() {
        showAlert(title: "Downloaded data is in wrong format", message: "Downloaded data is in wrong format " +
            "therefore cannot be parsed! Check if correct JSON file has been downloaded.", buttonText: "OK")
    }
    
    func getSavedPersitentArticleCount() -> Int? {
        return DataModel.getEntitiesCount(persistentContainer: persistentContainer, fetchRequest: articleFerchRequest)
    }
}

// MARK: - UITableViewDelegate
extension HeadingsTableVC : UITableViewDelegate
{
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
    }
}

// MARK: - UITableViewDataSource
extension HeadingsTableVC : UITableViewDataSource {
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

// MARK: NSFetchedResultsControllerDelegate
extension HeadingsTableVC: NSFetchedResultsControllerDelegate {
    func controllerWillChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.beginUpdates()
    }
    
    func controllerDidChangeContent(_ controller: NSFetchedResultsController<NSFetchRequestResult>) {
        tableView.endUpdates()
        updateView()
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange anObject: Any,
                    at indexPath: IndexPath?, for type: NSFetchedResultsChangeType, newIndexPath: IndexPath?) {
        switch (type) {
        case .insert:
            if let indexPath = newIndexPath {
                tableView.insertRows(at: [indexPath], with: .none)
            }
            break;
        case .delete:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .fade)
            }
            break;
        case .update:
            if let indexPath = indexPath, let cell = tableView.cellForRow(at: indexPath) as? HeadingsTableViewCell {
                configure(cell, at: indexPath)
            }
            break;
        case .move:
            if let indexPath = indexPath {
                tableView.deleteRows(at: [indexPath], with: .none)
            }
            
            if let newIndexPath = newIndexPath {
                tableView.insertRows(at: [newIndexPath], with: .none)
            }
            break;
        }
    }
    
    func controller(_ controller: NSFetchedResultsController<NSFetchRequestResult>, didChange sectionInfo: NSFetchedResultsSectionInfo,
                    atSectionIndex sectionIndex: Int, for type: NSFetchedResultsChangeType) {
        switch type {
        case .insert:
            tableView.insertSections(IndexSet(integer: sectionIndex), with: .fade)
        case .delete:
            tableView.deleteSections(IndexSet(integer: sectionIndex), with: .fade)
        default:
            break;
        }
    }
}
