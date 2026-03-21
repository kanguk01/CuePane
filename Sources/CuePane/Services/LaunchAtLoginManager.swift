import Foundation
import ServiceManagement

@MainActor
final class LaunchAtLoginManager {
    struct State {
        let isEnabled: Bool
        let message: String
    }

    func currentState() -> State {
        let status = SMAppService.mainApp.status

        switch status {
        case .enabled:
            return State(isEnabled: true, message: "로그인 시 자동 실행이 켜져 있습니다.")
        case .requiresApproval:
            return State(isEnabled: false, message: "시스템 설정에서 로그인 항목 승인이 필요합니다.")
        case .notFound:
            return State(isEnabled: false, message: "앱 번들이 등록 상태가 아니라 직접 실행 중일 수 있습니다.")
        case .notRegistered:
            return State(isEnabled: false, message: "로그인 시 자동 실행이 꺼져 있습니다.")
        @unknown default:
            return State(isEnabled: false, message: "로그인 시 실행 상태를 확인할 수 없습니다.")
        }
    }

    func setEnabled(_ enabled: Bool) throws -> State {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }

        return currentState()
    }
}
