//
//  SearchQueryDTO.swift
//  LaPioche
//
//  Created by Apprenant76 on 17/11/2026.
//

import Vapor

struct SearchQueryDTO: Content {
    let q: String?
    let players: Int?
    let maxDuration: Int?
    let available: Bool?
}
