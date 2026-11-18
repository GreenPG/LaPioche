@testable import App
import XCTVapor

final class LoanTests: XCTestCase {
    private func borrow(
        _ app: Application,
        gameID: UUID,
        memberID: UUID,
        token: String,
        afterResponse: (XCTHTTPResponse) async throws -> Void
    ) async throws {
        try await app.test(.POST, "loans", beforeRequest: { req in
            try req.content.encode(CreateLoanDTO(gameID: gameID, memberID: memberID))
            req.headers.bearerAuthorization = BearerAuthorization(token: token)
        }, afterResponse: afterResponse)
    }

    func testBorrowGameReturnsCreated() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let member = try await createMember(app, token: token)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id), token: token
            ) { res in
                XCTAssertEqual(res.status, .created)
                let loan = try res.content.decode(LoanDTO.self)
                XCTAssertEqual(loan.gameID, game.id)
                XCTAssertEqual(loan.memberID, member.id)
                XCTAssertNil(loan.returnedAt)
            }
        }
    }

    func testDueDateIsFourteenDaysAfterBorrowDate() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let member = try await createMember(app, token: token)

            try await borrow(
                app, gameID: try XCTUnwrap(game.id), memberID: try XCTUnwrap(member.id), token: token
            ) { res in
                let loan = try res.content.decode(LoanDTO.self)
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(secondsFromGMT: 0)!
                let days = calendar.dateComponents([.day], from: loan.borrowedAt, to: loan.dueAt).day
                XCTAssertEqual(days, 14)
            }
        }
    }

    func testBorrowedGameIsNoLongerAvailable() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let member = try await createMember(app, token: token)
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(member.id), token: token) { _ in }

            try await app.test(
                .GET,
                "games/\(gameID)",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    XCTAssertFalse(try res.content.decode(GameDTO.self).isAvailable)
                })
        }
    }

    func testBorrowingAGameAlreadyOnLoanReturnsConflict() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let first = try await createMember(app, email: "first@example.com", token: token)
            let second = try await createMember(app, name: "Alex", email: "second@example.com", token: token)
            let gameID = try XCTUnwrap(game.id)

            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(first.id), token: token) { _ in }
            try await borrow(app, gameID: gameID, memberID: try XCTUnwrap(second.id), token: token) { res in
                XCTAssertEqual(res.status, .conflict)
            }
        }
    }

    func testBorrowUnknownGameReturnsNotFound() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let member = try await createMember(app, token: token)

            try await borrow(app, gameID: UUID(), memberID: try XCTUnwrap(member.id), token: token) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testBorrowWithUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)

            try await borrow(app, gameID: try XCTUnwrap(game.id), memberID: UUID(), token: token) { res in
                XCTAssertEqual(res.status, .notFound)
            }
        }
    }

    func testReturnLoanReturnsOK() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let member = try await createMember(app, token: token)
            let loan = try await insertLoan(
                app,
                gameID: XCTUnwrap(game.id),
                memberID: XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: Date().addingTimeInterval(14 * 24 * 60)
            )
            let id = try XCTUnwrap(loan.id)

            try await app.test(
                .POST,
                "loans/\(id)/return",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let returnedLoan = try res.content.decode(LoanDTO.self)
                    XCTAssertNotNil(returnedLoan.returnedAt)
                }
            )
        }
    }

    func testReturnLoanWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            try await app.test(
                .POST,
                "loans/not_an_id/return",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testReturnLoanUnknonwRetursnNotFound() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            try await app.test(
                .POST,
                "loans/\(UUID())/return",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }

    func testReturnLoanAlreadyReturnedRetursnConflict() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let member = try await createMember(app, token: token)
            let loan = try await insertLoan(
                app,
                gameID: XCTUnwrap(game.id),
                memberID: XCTUnwrap(member.id),
                borrowedAt: Date(),
                dueAt: Date().addingTimeInterval(14 * 24 * 60),
                returnedAt: Date()
            )
            let id = try XCTUnwrap(loan.id)

            try await app.test(
                .POST,
                "loans/\(id)/return",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testLoanOverdueReturnsOK() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let member = try await createMember(app, token: token)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)
            let _ = try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: Date().addingTimeInterval(-10 * 24 * 60),
                dueAt: Date().addingTimeInterval(-1 * 24 * 60)
            )

            try await app.test(
                .GET,
                "loans/overdue",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let overduedLoans = try res.content.decode([LoanDTO].self)
                    XCTAssertEqual(overduedLoans.count, 1)
                    XCTAssertEqual(overduedLoans.first?.gameID, gameID)
                    XCTAssertEqual(overduedLoans.first?.memberID, memberID)
                }
            )
        }
    }

    func testLoanOverdueOnlyReturnedLoansReturnOK() async throws {
        try await withApp { app in
            let user = try await registerUser(app)
            let token = try XCTUnwrap(user.token)
            let game = try await createGame(app, token: token)
            let member = try await createMember(app, token: token)
            let gameID = try XCTUnwrap(game.id)
            let memberID = try XCTUnwrap(member.id)
            let _ = try await insertLoan(
                app,
                gameID: gameID,
                memberID: memberID,
                borrowedAt: Date().addingTimeInterval(-10 * 24 * 60),
                dueAt: Date().addingTimeInterval(-1 * 24 * 60),
                returnedAt: Date().addingTimeInterval(-5 * 24 * 60)
            )

            try await app.test(
                .GET,
                "loans/overdue",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: token)
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let overduedLoans = try res.content.decode([LoanDTO].self)
                    XCTAssertEqual(overduedLoans.count, 0)
                }
            )
        }
    }

    func testCreateLoanWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testReturnLoanWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "loans/\(UUID())/return",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testListOverdueLoansWithoutTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "loans/overdue",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testCreateLoanWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "loans",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testReturnLoanWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .POST,
                "loans/\(UUID())/return",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testListOverdueLoansWithWrongTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "loans/overdue",
                beforeRequest: { req in
                    req.headers.bearerAuthorization = BearerAuthorization(token: "wrong_token")
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testCreateLoanWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .POST,
                "loans",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(token: XCTUnwrap(user.token))
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testReturnLoanWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .POST,
                "loans/\(UUID())/return",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(token: XCTUnwrap(user.token))
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }

    func testListOverdueLoansWithExpiredTokenReturnsUnauthorized() async throws {
        try await withApp { app in
            let user = try await registerUserWithExpiredToken(app)
            try await app.test(
                .GET,
                "loans/overdue",
                beforeRequest: { req in
                    try req.headers.bearerAuthorization = BearerAuthorization(token: XCTUnwrap(user.token))
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .unauthorized)
                }
            )
        }
    }
}
