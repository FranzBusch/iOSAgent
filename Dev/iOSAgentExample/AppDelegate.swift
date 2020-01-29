//
//  AppDelegate.swift
//  iOSAgentExample
//
//  Created by Christian Menschel on 22.11.19.
//  Copyright © 2019 Instana Inc. All rights reserved.
//

import UIKit
import InstanaAgent

@UIApplicationMain
class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Instana.setup(key: InstanaKey, reportingURL: InstanaURL)
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Called when a new scene session is being created.
        // Use this method to select a configuration to create the new scene with.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Called when the user discards a scene session.
        // If any sessions were discarded while the application was not running, this will be called shortly after application:didFinishLaunchingWithOptions.
        // Use this method to release any resources that were specific to the discarded scenes, as they will not return.
    }
}

var InstanaKey: String {
    if let launchArgs = UserDefaults.standard.string(forKey: "key") {
        return launchArgs
    }
    return Bundle.main.infoDictionary?["INSTANA_REPORTING_KEY"] as? String ?? ""
}

var InstanaURL: URL {
    var value = ""
    if let launchArgs = UserDefaults.standard.string(forKey: "reportingURL") {
        value = launchArgs
    } else if let plistValue = Bundle.main.infoDictionary?["INSTANA_REPORTING_URL"] as? String {
        value = plistValue
    }
    return URL(string: value)!
}
