//
//  RegisterDTO.swift
//  LaPioche
//
//  Created by Apprenant76 on 18/11/2026.
//

import Vapor

struct RegisterDTO: Content {
    var email: String
    var password: String
}

extension RegisterDTO {
    func toModel() -> User {
        return User(
            email: email,
            password: password
        )
    }
}
