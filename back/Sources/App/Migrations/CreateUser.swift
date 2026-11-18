//
//  CreateUser.swift
//  LaPioche
//
//  Created by Apprenant76 on 18/11/2026.
//

import Fluent

struct CreateUser: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database
            .schema(User.schema)
            .id()
            .field(
                "email",
                .string,
                .required
            )
            .field(
                "password",
                .string,
                .required
            )
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database
            .schema(User.schema)
            .delete()
    }
}
