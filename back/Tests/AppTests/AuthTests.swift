//
//  AuthTests.swift
//  LaPioche
//
//  Created by Apprenant76 on 18/11/2026.
//

@testable import App
import XCTVapor

final class AuthTests: XCTestCase {
    func testRegisterUserReturnsOK() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "/auth/register",
                beforeRequest: { req in
                    try req.content.encode(
                        RegisterDTO(
                            email: "camille@example.com",
                            password: "password"
                        )
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .created)
                    let auth = try res.content.decode(AuthDTO.self)
                    XCTAssertTrue(auth.user.id != nil)
                    XCTAssertEqual(auth.user.email, "camille@example.com")
                }
            )
        }
    }

    func testRegisterUserWithTooShortPasswordReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "/auth/register",
                beforeRequest: { req in
                    try req.content.encode(
                        RegisterDTO(
                            email: "camille@example.com",
                            password: "short"
                        )
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testRegisterUserWithMalformedEmailReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "/auth/register",
                beforeRequest: { req in
                    try req.content.encode(
                        RegisterDTO(
                            email: "not_an_email",
                            password: "password"
                        )
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testRegisterUserEmailAlreadyUsedReturnsConflict() async throws {
        try await withApp { app in
            let _ = try await registerUser(app)
            try await app.test(
                .POST,
                "/auth/register",
                beforeRequest: { req in
                    try req.content.encode(
                        RegisterDTO(
                            email: "camille@example.com",
                            password: "password"
                        )
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testLoginRetursnOK() async throws {
        try await withApp { app in
            let _ = try await registerUser(app)

            try await app.test(
                .POST,
                "auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginDTO(
                        email: "camille@example.com", password: "password"))
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let auth = try res.content.decode(AuthDTO.self)
                    XCTAssertTrue(auth.user.id != nil)
                    XCTAssertEqual(auth.user.email, "camille@example.com")
                }
            )
        }
    }

    func testLoginWithWrongEmailRetursUnauthorized() async throws {
        try await withApp { app in
            let _ = try await registerUser(app)

            try await app.test(
                .POST,
                "auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginDTO(
                        email: "wrong@example.com", password: "password"))
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testLoginWithWrongPasswordRetursUnauthorized() async throws {
        try await withApp { app in
            let _ = try await registerUser(app)

            try await app.test(
                .POST,
                "auth/login",
                beforeRequest: { req in
                    try req.content.encode(LoginDTO(
                        email: "camille@example.com", password: "wrong_password"))
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testGetMeReturnsOK() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            try await app.test(
                .GET,
                "auth/me",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let data = try res.content.decode(UserDTO.self)
                    XCTAssertEqual(data.id, try XCTUnwrap(user.user.id))
                    XCTAssertEqual(data.email, try XCTUnwrap(user.user.email))
                }
            )
        }
    }

    func testGetMeWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let _ = try await registerUser(app)
            try await app.test(
                .GET,
                "auth/me",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testGetMeWithBadTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let _ = try await registerUser(app)
            try await app.test(
                .GET,
                "auth/me",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "not a token")
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }
}
