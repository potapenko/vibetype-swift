//
//  DictationSessionControllerRecordingActions.swift
//  vibetype
//
//  Created by Codex on 6/22/26.
//

extension DictationSessionController {
    func startRecordingAction() async {
        switch status {
        case .idle, .success, .failure:
            await performRecordingAction()
        case .recording, .transcribing:
            return
        }
    }

    func stopRecordingAction() async {
        guard status == .recording else {
            return
        }

        await performRecordingAction()
    }
}
