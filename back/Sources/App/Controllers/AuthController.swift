//
//  AuthController.swift
//  LaPioche
//
//  Created by Apprenant76 on 18/11/2026.
//

import Fluent
import Vapor
import JWT

struct AuthController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let auth = routes.grouped("auth")

        auth.post("register", use: create)
        auth.post("login", use: login)

        let protected = auth.grouped(JWTMiddleware())
        protected.get("me", use: get)
    }

    func create(req: Request) async throws -> Response {
        var newUser = try req.content.decode(RegisterDTO.self)
        guard newUser.password.count >= 8 else {
            throw Abort(.badRequest, reason: "Wrong password")
        }
        let emailRegex = try Regex("[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}")
        guard newUser.email.contains(emailRegex) else {
            throw Abort(.badRequest, reason: "Wrong email")
        }

        if let _ = try await User
            .query(on: req.db)
            .filter(\.$email == newUser.email)
            .first() {
            throw Abort(.conflict, reason: "Email already used")
        }
        newUser.password = try Bcrypt.hash(newUser.password)
        let userToSave = newUser.toModel()
        try await userToSave.save(on: req.db)

        guard let jwtKey = Environment.get("JWT_KEY") else {
            throw Abort(.internalServerError, reason: "JWT key not found")
        }
        let payload = UserPayload(id: userToSave.id!)
        let signer = JWTSigner.hs256(key: jwtKey)
        let jwToken = try signer.sign(payload)

        return try await AuthDTO(
            token: jwToken,
            expiresAt: payload.expiration,
            user: userToSave.toDTO()
        ).encodeResponse(status: .created, for: req)
    }

    func login(req: Request) async throws -> AuthDTO {
        let loginDTO = try req.content.decode(LoginDTO.self)

        guard let user = try await User
            .query(on: req.db)
            .filter(\.$email == loginDTO.email)
            .first() else {
            throw Abort(.unauthorized, reason: "Wrong email")
        }

        guard try Bcrypt.verify(loginDTO.password , created: user.password) else {
            throw Abort(.unauthorized, reason: "Wrong password")
        }

        guard let jwtKey = Environment.get("JWT_KEY") else {
            throw Abort(.internalServerError, reason: "JWT key not found")
        }
        let payload = UserPayload(id: user.id!)
        let signer = JWTSigner.hs256(key: jwtKey)
        let jwToken = try signer.sign(payload)

        return AuthDTO(
            token: jwToken,
            expiresAt: payload.expiration,
            user: user.toDTO()
        )
    }

    func get(req: Request) async throws -> UserDTO {
        guard let payload = req.auth.get(UserPayload.self) else {
            throw Abort(.unauthorized)
        }

        guard let user = try await User.find(payload.id, on: req.db) else {
            throw Abort(.unauthorized)
        }
        return user.toDTO()
    }
}
