# Action Items & TODOs

## Local Storage & Alerts Memory
- [x] **Database Schema**: Implement SQLite schema for SOS packets (`packets`), seen markers (`seen_packets`), and broadcast queue (`broadcast_queue`).
- [x] **Deduplication Logic**: Ensure only newer sequence numbers from the same user are stored to save space.
- [x] **Automatic Cleanup**: Implement periodic cleanup (currently set to 30 mins) to remove expired packets (> 24h).
- [ ] **Alert History UI**: Create a dedicated "Alerts History" page to view all previously received signals, even if they are no longer active on the map.
- [ ] **Persistent Notifications**: Ensure received alerts are added to system notifications so they aren't missed when the app is in the background.
- [ ] **Export Data**: Add ability to export received SOS data as CSV/JSON for rescue coordination.

## Local Cache Management
- [x] **Clear Cache Functionality**: Implemented "Clear local data" in Settings.
  - [x] Wipes all SOS packets from SQLite.
  - [x] Resets the seen packet deduplication table.
  - [x] Clears the broadcast relay queue.
  - [x] Triggers OfflineMapService cache clearing.
- [ ] **Granular Cache Control**: Allow users to clear map data and SOS data independently.
- [ ] **Cache Size Indicator**: Show current disk usage by SOS packets and Map tiles in the Settings page.

## Stability & Performance
- [x] **iOS Deployment Target**: Minimum deployment target set to 15.6 for all pods.
- [x] **Icon Tree Shaking**: Refactored SOSStatus to use static IconData for production build compatibility.
- [ ] **Memory Management**: Monitor memory usage when the `broadcast_queue` grows large in high-density areas.
