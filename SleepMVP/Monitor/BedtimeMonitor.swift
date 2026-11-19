import DeviceActivity

final class BedtimeMonitor: DeviceActivityMonitor {
    override func intervalDidEnd(for activity: DeviceActivityName) {
        super.intervalDidEnd(for: activity)
        guard activity == Restriction.activity else { return }
        Restriction.clearIfExpired()
    }
}
