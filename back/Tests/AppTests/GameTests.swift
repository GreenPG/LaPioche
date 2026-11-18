@testable import App
import XCTVapor

final class GameTests: XCTestCase {
    func testCreateGameReturnsCreated() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .POST,
                "games",
                beforeRequest: { req in
                    try req.content.encode(CreateGameDTO(
                        title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                    ))
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .created)
                    let game = try res.content.decode(GameDTO.self)
                    XCTAssertEqual(game.title, "Catan")
                    XCTAssertTrue(game.isAvailable)
                })
        }
    }

    func testCreateGameWithEmptyTitleIsRejected() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                ))
                try req.headers.bearerAuthorization = BearerAuthorization(
                    token: XCTUnwrap(user.token)
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateGameWithInvertedPlayerBoundsIsRejected() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(.POST, "games", beforeRequest: { req in
                try req.content.encode(CreateGameDTO(
                    title: "Catan", minPlayers: 5, maxPlayers: 2, durationMinutes: 90
                ))
                try req.headers.bearerAuthorization = BearerAuthorization(
                    token: XCTUnwrap(user.token)
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testListGames() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            _ = try await createGame(app, title: "Catan", token: token)
            _ = try await createGame(app, title: "Dixit", token: token)

            try await app.test(.GET, "games", beforeRequest:  { req in
                req.headers.bearerAuthorization = BearerAuthorization(
                    token: token
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode([GameDTO].self).count, 2)
            })
        }
    }

    func testShowGame() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let id = try XCTUnwrap(game.id)

            try await app.test(.GET, "games/\(id)",
                               beforeRequest: { req in
                req.headers.bearerAuthorization = BearerAuthorization(
                    token: token
                )
            },
                               afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(try res.content.decode(GameDTO.self).id, id)
            })
        }
    }

    func testShowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .GET,
                "games/\(UUID())",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                })
        }
    }

    func testShowGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .GET,
                "games/not-a-uuid",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                })
        }
    }

    func testPreflightRequestFromAnotherOriginIsAllowed() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(.OPTIONS, "games", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                req.headers.replaceOrAdd(name: .accessControlRequestMethod, value: "POST")
                req.headers.replaceOrAdd(name: .accessControlRequestHeaders, value: "content-type")
                try req.headers.bearerAuthorization = BearerAuthorization(
                    token: XCTUnwrap(user.token)
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .ok)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
                XCTAssertTrue(res.headers[.accessControlAllowMethods].joined(separator: ",").contains("POST"))
            })
        }
    }

    func testErrorResponsesCarryTheCorsHeaders() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(.GET, "games/not-a-uuid", beforeRequest: { req in
                req.headers.replaceOrAdd(name: .origin, value: "http://localhost:8080")
                try req.headers.bearerAuthorization = BearerAuthorization(
                    token: XCTUnwrap(user.token)
                )
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
                XCTAssertEqual(res.headers.first(name: .accessControlAllowOrigin), "*")
            })
        }
    }

    func testModifyGame() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let id = try XCTUnwrap(game.id)

            try await app.test(
                .PUT,
                "games/\(id)",
                beforeRequest: { req in
                    try req.content.encode(
                        ModifyGameDTO(
                            title: "Dixit",
                            minPlayers: 2,
                            maxPlayers: 10,
                            durationMinutes: 60
                        )
                    )
                    req.headers.bearerAuthorization = BearerAuthorization(
                        token: token
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let game = try res.content.decode(GameDTO.self)
                    XCTAssertEqual(game.title, "Dixit")
                    XCTAssertEqual(game.minPlayers, 2)
                    XCTAssertEqual(game.maxPlayers, 10)
                    XCTAssertEqual(game.durationMinutes, 60)
                }
            )
        }
    }

    func testModifyGameUnknownGameReturnsNotFound () async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .PUT,
                "games/\(UUID())",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }

    func testModifyGameWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .PUT,
                "games/not-a-uuid",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testModifyGameWithMalformedBodyReturnsBadRequest() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let id = try XCTUnwrap(game.id)
            try await app.test(
                .PUT,
                "games/\(id)",
                beforeRequest: {req in
                    try req.content.encode(
                        ModifyGameDTO(
                            title: "",
                            minPlayers: 2,
                            maxPlayers: 10,
                            durationMinutes: 60)
                    )
                    req.headers.bearerAuthorization = BearerAuthorization(
                        token: token
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testDeleteGame() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let id = try XCTUnwrap(game.id)

            try await app.test(
                .DELETE,
                "games/\(id)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(
                        token: token
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .noContent)
                }
            )
        }
    }

    func testDeleteUnknowGameReturnsNotFound() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .DELETE,
                "games/\(UUID())",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }

    func testDeleteLoanedGameReturnsConflict() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let gameID = try XCTUnwrap(game.id)
            let member = try await createMember(app, token: token)
            let memberID = try XCTUnwrap(member.id)
            let _ = try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: Date(),
                dueAt: try Loan.dueDate(from: Date())
            )


            try await app.test(
                .DELETE,
                "games/\(gameID)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(
                        token: token
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testSearchGameReturnsOK() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let _ = try await createGame(app, title: "Dixit", token: token)

            try await app.test(
                .GET,
                "games?q=catan&players=\(game.minPlayers)&maxDuration=\(game.durationMinutes)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(
                        token: token
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let data = try res.content.decode([GameDTO].self)
                    XCTAssertEqual(data.count, 1)
                    XCTAssertEqual(data.first?.title, game.title)
                }
            )
        }
    }

    func testSearchGameWithBadMaxDurationReturnsConflict() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .GET,
                "games?players=0",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testSearchGameWithBadPlayersReturnsConflict() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            try await app.test(
                .GET,
                "games?maxDuration=-10",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testSearchAvailableGamesReturnsOK() async throws {
        try await withApp { app in
            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let availableGame = try await createGame(app, token: token)
            let unavailableGame = try await createGame(app, title: "Dixit", token: token)
            let member = try await createMember(app, token: token)
            let _ = try await insertLoan(
                app,
                gameID: XCTUnwrap(unavailableGame.id),
                memberID: XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: Date().addingTimeInterval(14 * 24 * 60)
            )

            try await app.test(
                .GET,
                "games?available=true",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(
                        token: token
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let games = try res.content.decode([GameDTO].self)
                    XCTAssertEqual(games.count, 1)
                    XCTAssertEqual(games.first?.title, availableGame.title)
                }
            )
        }
    }

    func testSearchUnavailableGamesReturnsOK() async throws {
        try await withApp { app in

            let user  = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let _ = try await createGame(app, token: token)
            let unavailableGame = try await createGame(app, title: "Dixit", token: token)
            let member = try await createMember(app, token: token)
            let _ = try await insertLoan(
                app,
                gameID: XCTUnwrap(unavailableGame.id),
                memberID: XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: Date().addingTimeInterval(14 * 24 * 60)
            )

            try await app.test(
                .GET,
                "games?available=false",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(
                        token: token
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let games = try res.content.decode([GameDTO].self)
                    XCTAssertEqual(games.count, 1)
                    XCTAssertEqual(games.first?.title, unavailableGame.title)
                }
            )
        }
    }

    func testListGamesWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            _ = try await createGame(app, title: "Catan", token: token)
            _ = try await createGame(app, title: "Dixit", token: token)

            try await app.test(.GET, "games", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testCreateGameWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "games",
                beforeRequest: { req in
                    try req.content.encode(CreateGameDTO(
                        title: "Catan", minPlayers: 3, maxPlayers: 4, durationMinutes: 90
                    ))
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                })
        }
    }

    func testShowGameWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let game = try await createGame(app, token: XCTUnwrap(user.token))
            let id = try XCTUnwrap(game.id)

            try await app.test(.GET, "games/\(id)", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testUpdateGameWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let game = try await createGame(app, token: XCTUnwrap(user.token))
            let id = try XCTUnwrap(game.id)

            try await app.test(
                .PUT,
                "games/\(id)",
                beforeRequest: { req in
                    try req.content.encode(
                        ModifyGameDTO(
                            title: "Dixit",
                            minPlayers: 2,
                            maxPlayers: 10,
                            durationMinutes: 60
                        )
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testDeleteGameWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let game = try await createGame(app, token: XCTUnwrap(user.token))
            let id = try XCTUnwrap(game.id)

            try await app.test(
                .DELETE,
                "games/\(id)",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testListGamesWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "games",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testCreateGameWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "games",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testShowGameWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "games/\(UUID())",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testUpdateListGameWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .PUT,
                "games/\(UUID())",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testDeleteGameWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .DELETE,
                "games/\(UUID())",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testListGamesWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .GET,
                "games",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testCreateGameWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .POST,
                "games",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testShowGameWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .GET,
                "games/\(UUID())",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testModifyGameWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .PUT,
                "games/\(UUID())",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }

    func testDeleteGameWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .DELETE,
                "games/\(UUID())",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(
                        token: XCTUnwrap(user.token)
                    )
                },
                afterResponse: { res async throws in
                XCTAssertEqual(res.status, .unauthorized)
            })
        }
    }
}
