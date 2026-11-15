@testable import App
import XCTVapor

final class MemberTests: XCTestCase {
    func testCreateMemberReturnsCreated() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .created)
                XCTAssertEqual(try res.content.decode(MemberDTO.self).name, "Camille")
            })
        }
    }

    func testCreateMemberWithInvalidEmailIsRejected() async throws {
        try await withApp { app in
            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Camille", email: "not-an-email"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .badRequest)
            })
        }
    }

    func testCreateMemberWithDuplicateEmailReturnsConflict() async throws {
        try await withApp { app in
            _ = try await createMember(app)

            try await app.test(.POST, "members", beforeRequest: { req in
                try req.content.encode(CreateMemberDTO(name: "Autre", email: "camille@example.com"))
            }, afterResponse: { res async throws in
                XCTAssertEqual(res.status, .conflict)
            })
        }
    }

    func testShowUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(.GET, "members/\(UUID())", afterResponse: { res async throws in
                XCTAssertEqual(res.status, .notFound)
            })
        }
    }

    func testUpdateMemberReturnsOK() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.test(
                .PUT,
                "members/\(id)",
                beforeRequest: { req in
                    try req.content.encode(
                        ModifyMemberDTO(
                            name: "Marc",
                            email: "marc@example.com"
                        )
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let updatedMember = try res.content.decode(Member.self)
                    XCTAssertEqual(updatedMember.id, id)
                    XCTAssertEqual(updatedMember.name, "Marc")
                    XCTAssertEqual(updatedMember.email, "marc@example.com")
                }
            )
        }
    }

    func testModifyMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in

            try await app.test(
                .PUT,
                "members/not_an_id",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testModifyMemberUnknownMemberReturnNotFound() async throws {
        try await withApp { app in

            try await app.test(
                .PUT,
                "members/\(UUID())",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }

    func testModifyMemberEmailAlreadyUsedReturnsConflict() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let _ = try await createMember(app, email: "already_used@example.com")
            let id = try XCTUnwrap(member.id)

            try await app.test(
                .PUT,
                "members/\(id)",
                beforeRequest: { req in
                    try req.content.encode(
                        ModifyMemberDTO(
                            name: "Camille",
                            email: "already_used@example.com"
                        )
                    )
                },
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testDeleteMemberReturnsNoContent() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let id = try XCTUnwrap(member.id)

            try await app.test(
                .DELETE,
                "members/\(id)",
                afterResponse:  { res async throws in
                    XCTAssertEqual(res.status, .noContent)
                }
            )
        }
    }

    func testDeleteMemberWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(
                .DELETE,
                "members/not_an_id",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testDeleteMemberUnknownReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(
                .DELETE,
                "members/\(UUID())",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }
    func testDeleteMemberWithLoanReturnsConflict() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let game = try await createGame(app)
            let id = try XCTUnwrap(member.id)
            try await insertLoan(app, gameID: XCTUnwrap(game.id), memberID: id, borrowedAt: Date(), dueAt: Date())

            try await app.test(
                .DELETE,
                "members/\(id)",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .conflict)
                }
            )
        }
    }

    func testListMemberLoans() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)
            let game1 = try await createGame(app)
            let game2 = try await createGame(app, title: "Dixit")
            let _ = try await insertLoan(
                app,
                gameID: XCTUnwrap(game1.id),
                memberID: memberID,
                borrowedAt: Date(),
                dueAt: Date()
            )
            let _ = try await insertLoan(
                app,
                gameID: XCTUnwrap(game2.id),
                memberID: memberID,
                borrowedAt: Date(),
                dueAt: Date()
            )

            try await app.test(
                .GET,
                "members/\(memberID)/loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let loans = try res.content.decode([LoanDTO].self)
                    XCTAssertEqual(loans.count, 2)
                }
            )
        }
    }

    func testListMemberLoansEmpty() async throws {
        try await withApp { app in
            let member = try await createMember(app)
            let memberID = try XCTUnwrap(member.id)

            try await app.test(
                .GET,
                "members/\(memberID)/loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .ok)
                    let loans = try res.content.decode([LoanDTO].self)
                    XCTAssertEqual(loans.isEmpty, true)
                }
            )
        }
    }

    func testListMemberLoansWithMalformedIDReturnsBadRequest() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "members/not_an_id/loans",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .badRequest)
                }
            )
        }
    }

    func testListMemberLoansUnknownMemberReturnsNotFound() async throws {
        try await withApp { app in
            try await app.test(
                .GET,
                "members/\(UUID())/return",
                afterResponse: { res async throws in
                    XCTAssertEqual(res.status, .notFound)
                }
            )
        }
    }
}
