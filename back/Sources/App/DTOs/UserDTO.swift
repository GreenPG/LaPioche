//
//  UserDTO.swift
//  LaPioche
//
//  Created by Apprenant76 on 18/11/2026.
//
import Vapor

struct UserDTO: Content {
    let id: UUID?
    let email: String
}
