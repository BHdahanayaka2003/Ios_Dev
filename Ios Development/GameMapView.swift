import SwiftUI
import Combine
import MapKit
import CoreLocation
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Game Session Model

struct GameSession: Identifiable, Codable, Equatable, Hashable {
    let id: UUID
    let gameName: String
    let score: Int
    let date: Date
    var latitude: Double?
    var longitude: Double?

    init(id: UUID = UUID(), gameName: String, score: Int, date: Date = Date(),
         latitude: Double?, longitude: Double?) {
        self.id = id
        self.gameName = gameName
        self.score = score
        self.date = date
        self.latitude = latitude
        self.longitude = longitude
    }

    var coordinate: CLLocationCoordinate2D? {
        guard let latitude, let longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

// MARK: - Location Manager

@MainActor
final class LocationManager: NSObject, ObservableObject {

    static let shared = LocationManager()

    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus
    @Published var lastError: String?

    private let manager = CLLocationManager()

    override private init() {
        self.authorizationStatus = .notDetermined
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        self.authorizationStatus = manager.authorizationStatus
    }

    func requestPermission() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    func requestOneShotLocation() {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            manager.requestLocation()
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            lastError = "Location access is off. Enable it in Settings to pin your games on the map."
        @unknown default:
            break
        }
    }
}

extension LocationManager: CLLocationManagerDelegate {
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.currentLocation = location
            self.lastError = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.lastError = error.localizedDescription }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorizationStatus = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                manager.requestLocation()
            }
        }
    }
}

// MARK: - Session Store (persists to disk as JSON)

@MainActor
final class GameSessionStore: ObservableObject {
    static let shared = GameSessionStore()

    @Published private(set) var sessions: [GameSession] = []

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("game_sessions.json")
    }()

    // FIX: this used to be a single `UUID?`, which meant every new session
    // recorded before a GPS fix arrived would silently overwrite the last
    // one — so only the *most recent* pending session could ever be
    // backfilled, and every earlier one was permanently lost. Tracking a
    // Set means every session that finished before we had a location gets
    // patched once one becomes available.
    private var pendingSessionIDs: Set<UUID> = []
    private var locationCancellable: AnyCancellable?

    private init() {
        load()
        subscribeToLocationUpdates()
    }

    /// Call this whenever a round finishes. Grabs the freshest known location;
    /// if none is available yet, marks the session as "pending" so a later
    /// location fix can still attach coordinates to it.
    func recordSession(gameName: String, score: Int) {
        let loc = LocationManager.shared.currentLocation
        let session = GameSession(
            gameName: gameName,
            score: score,
            latitude: loc?.coordinate.latitude,
            longitude: loc?.coordinate.longitude
        )
        sessions.append(session)
        save()

        if loc == nil {
            pendingSessionIDs.insert(session.id)
            LocationManager.shared.requestOneShotLocation()
        }
    }

    func resetAll() {
        sessions.removeAll()
        pendingSessionIDs.removeAll()
        save()
    }

    // MARK: - Private

    private func subscribeToLocationUpdates() {
        locationCancellable = LocationManager.shared.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                self?.attachLocationToPendingSessions(location)
            }
    }

    // FIX: patches EVERY pending session, not just one, using the first
    // location fix that arrives. This is an approximation (a session that
    // ended a minute ago gets "now's" coordinate rather than its own exact
    // one), but it's the best available signal and is far better than
    // silently dropping the pin forever.
    private func attachLocationToPendingSessions(_ location: CLLocation) {
        guard !pendingSessionIDs.isEmpty else { return }

        var didUpdateAny = false
        for id in pendingSessionIDs {
            guard let index = sessions.firstIndex(where: { $0.id == id }) else { continue }
            sessions[index].latitude = location.coordinate.latitude
            sessions[index].longitude = location.coordinate.longitude
            didUpdateAny = true
        }

        pendingSessionIDs.removeAll()
        if didUpdateAny { save() }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([GameSession].self, from: data) else { return }
        sessions = decoded
    }

    private func save() {
        do {
            let data = try JSONEncoder().encode(sessions)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("GameSessionStore save failed: \(error)")
        }
    }
}

// MARK: - Map View

struct GameMapView: View {
    @EnvironmentObject var store: GameSessionStore
    @StateObject private var locationManager = LocationManager.shared

    @State private var cameraPosition: MapCameraPosition = .automatic
    @State private var selectedSession: GameSession?

    private var mappedSessions: [GameSession] {
        store.sessions.filter { $0.coordinate != nil }
    }

    var body: some View {
        NavigationStack {
            Group {
                if isPermissionDenied {
                    permissionDeniedState
                } else if mappedSessions.isEmpty && store.sessions.isEmpty {
                    emptyState
                } else if mappedSessions.isEmpty {
                    // NEW: sessions exist, but none of them have a
                    // coordinate. This used to fall through to the same
                    // generic "No games played yet" message even though
                    // games WERE played — which hides the real problem
                    // (no location fix ever arrived) instead of surfacing it.
                    unlocatedSessionsState
                } else {
                    mapView
                }
            }
            .navigationTitle("Play Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if !mappedSessions.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            updateCamera(animated: true)
                        } label: {
                            Image(systemName: "location.fill.viewfinder")
                        }
                        .accessibilityLabel("Recenter map")
                    }
                }
            }
            .onAppear {
                locationManager.requestPermission()
                locationManager.requestOneShotLocation()
                updateCamera(animated: false)
            }
            // FIX: camera was set once to `.automatic` and never touched
            // again, so it wouldn't follow new pins or a newly-acquired
            // user location. Recompute framing whenever either changes.
            .onChange(of: mappedSessions) { _ in
                updateCamera(animated: true)
            }
            .onChange(of: locationManager.currentLocation) { _ in
                updateCamera(animated: true)
            }
        }
    }

    private var isPermissionDenied: Bool {
        locationManager.authorizationStatus == .denied || locationManager.authorizationStatus == .restricted
    }

    private var mapView: some View {
        Map(position: $cameraPosition, selection: $selectedSession) {
            ForEach(mappedSessions) { session in
                if let coordinate = session.coordinate {
                    Marker(session.gameName, systemImage: icon(for: session.gameName), coordinate: coordinate)
                        .tint(color(for: session.gameName))
                        .tag(session)
                }
            }
            UserAnnotation()
        }
        .mapControls {
            MapUserLocationButton()
            MapCompass()
            MapScaleView()
        }
        .sheet(item: $selectedSession) { session in
            sessionDetail(session)
                .presentationDetents([.height(220)])
        }
    }

    // FIX: fits the camera to every pinned session (plus the user's current
    // location, if known) instead of leaving it at `.automatic` forever.
    // Falls back gracefully: single pin -> centered close zoom, multiple
    // pins -> bounding region with padding, nothing yet -> leave as-is.
    private func updateCamera(animated: Bool) {
        var coordinates = mappedSessions.compactMap { $0.coordinate }
        if let userCoordinate = locationManager.currentLocation?.coordinate {
            coordinates.append(userCoordinate)
        }
        guard !coordinates.isEmpty else { return }

        let newPosition: MapCameraPosition
        if coordinates.count == 1, let only = coordinates.first {
            newPosition = .region(
                MKCoordinateRegion(center: only, latitudinalMeters: 2000, longitudinalMeters: 2000)
            )
        } else {
            let lats = coordinates.map(\.latitude)
            let lons = coordinates.map(\.longitude)
            let minLat = lats.min()!, maxLat = lats.max()!
            let minLon = lons.min()!, maxLon = lons.max()!

            let center = CLLocationCoordinate2D(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            )
            let span = MKCoordinateSpan(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.02)
            )
            newPosition = .region(MKCoordinateRegion(center: center, span: span))
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.6)) {
                cameraPosition = newPosition
            }
        } else {
            cameraPosition = newPosition
        }
    }

    private func sessionDetail(_ session: GameSession) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(session.gameName)
                .font(.title2.bold())
            Label("Score: \(session.score)", systemImage: "star.fill")
                .foregroundStyle(.orange)
            Label(session.date.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // NEW: shown when games have been recorded but none have a location
    // fix yet. Surfaces the real CLLocationManager error (if any) instead
    // of pretending nothing was played — this is what was previously
    // hidden, making it look like the map was just "broken."
    private var unlocatedSessionsState: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.magnifyingglass")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Waiting on a Location Fix")
                .font(.headline)
            Text("\(store.sessions.count) game\(store.sessions.count == 1 ? "" : "s") recorded, but none have a map location yet.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            if let error = locationManager.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            } else {
                Text("If you're running in the Simulator, set Features → Location → a preset in the menu bar — the Simulator has no real GPS by default.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button("Try Again") {
                locationManager.requestOneShotLocation()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "map")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("No games played yet")
                .font(.headline)
            Text("Finish a round in any game and it'll show up here, pinned to where you played.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    // NEW: previously a denied/restricted permission fell through to the
    // generic "No games played yet" empty state, which is misleading —
    // the real problem is location access, and there was no way to fix it
    // from inside the app.
    private var permissionDeniedState: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.slash.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Location Access Off")
                .font(.headline)
            Text("Enable location access in Settings so finished games can be pinned on the map.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            #if canImport(UIKit)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            #endif
        }
    }

    private func icon(for gameName: String) -> String {
        switch gameName {
        case "Tap Game": return "hand.tap.fill"
        case "Light Up": return "lightbulb.fill"
        case "Quiz Rush": return "brain.head.profile"
        default: return "gamecontroller.fill"
        }
    }

    private func color(for gameName: String) -> Color {
        switch gameName {
        case "Tap Game": return .blue
        case "Light Up": return .yellow
        case "Quiz Rush": return .purple
        default: return .gray
        }
    }
}

#Preview {
    GameMapView()
        .environmentObject(GameSessionStore.shared)
}
