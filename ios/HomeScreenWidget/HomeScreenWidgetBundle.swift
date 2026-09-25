//
//  HomeScreenWidgetBundle.swift
//  HomeScreenWidget
//
//  Created by THINK COMPUTERS on 17/09/26.
//

import WidgetKit
import SwiftUI

@main
struct HomeScreenWidgetBundle: WidgetBundle {
    var body: some Widget {
        HomeScreenWidget()
        // Xcode's template also registered a Control Center "start timer" control. It belonged to
        // the template, not to this app, and shipping it would put a meaningless timer in somebody's
        // Control Center. The file stays in the target so it still compiles; it is simply not
        // published.
    }
}
