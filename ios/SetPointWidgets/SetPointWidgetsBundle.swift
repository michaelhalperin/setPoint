import SwiftUI
import WidgetKit

@main
struct SetPointWidgetsBundle: WidgetBundle {
    var body: some Widget {
        CheckInLiveActivity()
        SetPointTodayWidget()
        SetPointLockWidget()
    }
}
