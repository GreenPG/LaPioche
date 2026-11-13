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

}
