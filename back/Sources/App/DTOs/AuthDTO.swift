//
//  AuthDTO.swift
//  LaPioche
//
//  Created by Apprenant76 on 18/11/2026.
//

import Vapor

struct AuthDTO: Content {
    let token: String
    let expiresAt: Date
    let user: UserDTO
}
