//
//  DictationOutputIntent.swift
//  HoldType
//
//  Created by Codex on 7/5/26.
//

import HoldTypeDomain

typealias DictationOutputIntent = HoldTypeDomain.DictationOutputIntent

extension DictationOutputIntent {
    func merged(with intent: DictationOutputIntent) -> DictationOutputIntent {
        self == .translate || intent == .translate ? .translate : .standard
    }
}
