import SwiftUI
import WidgetKit

@main
struct AiSkyWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ConditionsWidget()
        NextHourWidget()
        AirQualityWidget()
        PrecipitationWidget()
        LocationsWidget()
    }
}
