//
//  InputViewController.swift
//  SugoiFridge
//
//  Created by Richard Hsu on 2020/3/8.
//  Copyright © 2020 TAR. All rights reserved.
//

import Alamofire
import AlamofireImage
import Parse
import SwiftyJSON
import UIKit

class InputViewController: UIViewController, UISearchBarDelegate, UITableViewDataSource, UITableViewDelegate, IngredientsDelegate {

    // MARK: - Properties
    @IBOutlet weak var tableView: UITableView!
    @IBOutlet weak var doneButton: UIButton!
    @IBOutlet weak var searchBar: UISearchBar!
    
    let downloader = ImageDownloader()
    var ingredientsList: [Ingredient] = []
    var ingredientToEdit : Ingredient?
    var indexToEdit : Int?
    
    
    // MARK: - Initialization
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Setting up delegates
        setupTableView()
        setupSearchBar()

        // UI Customizations
        customizeDoneButton()
    }
    
    func setupTableView() {
        tableView.delegate   = self
        tableView.dataSource = self
    }
    
    func setupSearchBar() {
        searchBar.delegate = self
    }
    
    func customizeDoneButton() {
        doneButton.layer.cornerRadius = CGFloat(CustomUI.cornerRadius.rawValue)
    }
    
    
    // MARK: - Table View DataSource
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return ingredientsList.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: ReuseIdentifiers.inputTableView.rawValue) as! IngredientTableViewCell
        
        let ingredient = ingredientsList[indexPath.row]

        cell.ingredientNameLabel.text = ingredient.name
        cell.amountLabel.text = String(format: "%.1f", ingredient.amount)
        cell.unitLabel.text   = ingredient.unit
        cell.drawerLabel.text = ingredient.aisle
        cell.compartmentLabel.text = ingredient.compartment
        cell.ingredientImage.image = ingredient.image

        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        
        // Get the ingredient that needs to be passed to next scene
        // and save it locally to be accessed later
        ingredientToEdit = ingredientsList[indexPath.row]
        indexToEdit      = indexPath.row
        
        performSegue(withIdentifier: SegueIdentifiers.editSegue.rawValue, sender: self)
    }
    
    
    // MARK: - Ingredients Delegate
    func updateIngredient(with newIngredient: Ingredient, at index: Int) {
        ingredientsList[index] = newIngredient
        tableView.reloadData()
    }
    
    
    // MARK: - Navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        if (segue.identifier == SegueIdentifiers.editSegue.rawValue) {
            let destinationVC = segue.destination as! EditViewController
            
            destinationVC.delegate   = self
            destinationVC.ingredient = ingredientToEdit
            destinationVC.index      = indexToEdit
        }
    }
    
    
    // MARK: - Search Bar Functions
    func searchBarSearchButtonClicked(_ searchBar: UISearchBar) {
        // Check if search bar is empty
        if searchBar.text == "" {
            AlertControl.control.displayAlert(inVC: self, withTitle: ErrorMessages.searchTitle.rawValue, andMsg: ErrorMessages.emptySearchMsg.rawValue)
        }
        else {
            parseIngredientsRequest()
            searchBar.text = ""
        }
    }
    
    
    // MARK: - Actions
    @IBAction func onDone(_ sender: Any) {
        // loop through each ingredient in ingredientsList, and save each one
        // to the database
        for ingredient in ingredientsList {
            saveIngredient(ingredient)
        }
        
        performSegue(withIdentifier: SegueIdentifiers.fridgeSegue.rawValue, sender: nil)
    }
    
    
    // MARK: - Parse Database
    func saveIngredient(_ ingredient: Ingredient) {
        // Get table on parse to save foods in
        let food = PFObject(className: FoodDB.className.rawValue)
        
        food[FoodDB.user.rawValue]          = PFUser.current()!
        food[FoodDB.foodID.rawValue]        = ingredient.id
        food[FoodDB.foodName.rawValue]      = ingredient.name
        food[FoodDB.compartment.rawValue]   = ingredient.compartment
        food[FoodDB.aisle.rawValue]         = ingredient.aisle
        food[FoodDB.quantity.rawValue]      = ingredient.amount
        food[FoodDB.unit.rawValue]          = ingredient.unit
        food[FoodDB.possibleUnits.rawValue] = ingredient.possibleUnits
        food[FoodDB.imageName.rawValue]     = ingredient.imageName
        
        // Load image into Parse Object
        let imageData = ingredient.image.pngData()
        let file      = PFFileObject(name: "image.png", data: imageData!)
        food[FoodDB.image.rawValue] = file
        
        // Save new food ingredient parse object onto the database
        food.saveInBackground { (success, error) in
            if success {
                print("Ingredient \(ingredient.name) saved successfully to parse\n")
            }
            else {
                print("Error when saving \(ingredient.name) to Parse:\n\(error!.localizedDescription)")
                AlertControl.control.displayAlert(inVC: self, withTitle: ErrorMessages.generalTitle.rawValue, andMsg: "Error when saving \(ingredient.name) to server! Please try again later.")
            }
        }
    }
    
    
    // MARK: - Spoonacular Network Requests
    func parseIngredientsRequest() {
        var url = SpoonacularAPI.baseURL.rawValue + SpoonacularAPI.parseIngredient.rawValue
        url += "?apiKey=\(SpoonacularAPI.richAPIKey.rawValue)"
        
        let headers: HTTPHeaders = ["Content-Type": "application/x-www-form-urlencoded"]
        let parameters: [String : Any] = ["ingredientList": searchBar.text!, "servings": 1]
        
        AF.request(url, method: .post, parameters: parameters, encoding: URLEncoding.default, headers: headers)
            .validate().responseJSON { response in
                switch response.result {
                    case .success(let value):
                        print("Spoonacular API request successful\n")
                        
                        let jsonData = JSON(value)
                        self.parseIngredient(from: jsonData)
                    
                        self.tableView.reloadData()
                        
                    case .failure(let error):
                        print("Spoonacular API request failed\n")
                        AlertControl.control.displayAlert(inVC: self,withTitle: ErrorMessages.searchTitle.rawValue, andMsg: error.localizedDescription)
                }
        }
    }
    
    
    // MARK: - Data Parsing
    func parseIngredient(from data: JSON) {
        // data passed in is a list of length 1
        let data = data[0]
        
        let id     = data["id"].intValue
        let name   = data["name"].stringValue
        let unit   = data["unitShort"].stringValue
        let amount = data["amount"].doubleValue
        let aisle  = data["aisle"].stringValue
        let posUnits = data["possibleUnits"].arrayValue.map { $0.stringValue }
        let estCosts = data["estimatedCost"].dictionaryValue
        
        // Download ingredient image
        let imageString  = data["image"].stringValue
        let urlString = SpoonacularAPI.image.rawValue + ImageSize.small.rawValue + "/" + imageString
        let url = URL(string: urlString)!
        let urlRequest = URLRequest(url: url)

        downloader.download(urlRequest) { response in
            switch response.result {
                // If download image is successful, add the image to the
                // the ingredients list to be displayed
                case .success(let image):
                    print("Obtained \"\(name)\" image successfully\n")
                    // Add ingredient to list
                    let ingredient = Ingredient(id: id, name: name, image: image, imageName: imageString, unit: unit, amount: amount, aisle: aisle, cost: estCosts, possibleUnits: posUnits)
                    
                    self.ingredientsList.append(ingredient)
                    self.tableView.reloadData()
                
                // If download image failed, add an empty image to the
                // ingredients list
                case .failure( _):
                    print("Failed to obtain \"\(name)\" image\n")
                    let image = UIImage()
                
                    let ingredient = Ingredient(id: id, name: name, image: image, imageName: imageString, unit: unit, amount: amount, aisle: aisle, cost: estCosts, possibleUnits: posUnits)
                    
                    self.ingredientsList.append(ingredient)
                    self.tableView.reloadData()
            }
        }
    }
}