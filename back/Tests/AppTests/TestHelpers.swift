@testable import App
import XCTVapor
import JWT

func withApp(_ test: (Application) async throws -> Void) async throws {
    let app = try await Application.make(.testing)
    do {
        try await configure(app)
        try await test(app)
    } catch {
        try? await app.asyncShutdown()
        throw error
    }
    try await app.asyncShutdown()
}

func createGame(
    _ app: Application,
    title: String = "Catan",
    minPlayers: Int = 3,
    maxPlayers: Int = 4,
    durationMinutes: Int = 90,
    token: String
) async throws -> GameDTO {
    var game: GameDTO?
    try await app.test(.POST, "games", beforeRequest: { req in
        try req.content.encode(CreateGameDTO(
            title: title,
            minPlayers: minPlayers,
            maxPlayers: maxPlayers,
            durationMinutes: durationMinutes
        ))
        req.headers.bearerAuthorization = BearerAuthorization(token: token)
    }, afterResponse: { res async throws in
        game = try res.content.decode(GameDTO.self)
    })
    return try XCTUnwrap(game)
}

func createMember(
    _ app: Application,
    name: String = "Camille",
    email: String = "camille@example.com",
    token: String
) async throws -> MemberDTO {
    var member: MemberDTO?
    try await app.test(.POST, "members", beforeRequest: { req in
        try req.content.encode(CreateMemberDTO(name: name, email: email))
        req.headers.bearerAuthorization = BearerAuthorization(token: token)
    }, afterResponse: { res async throws in
        member = try res.content.decode(MemberDTO.self)
    })
    return try XCTUnwrap(member)
}

// The API cannot create a loan that is already late, so tests insert it directly.
func insertLoan(
    _ app: Application,
    gameID: UUID,
    memberID: UUID,
    borrowedAt: Date,
    dueAt: Date,
    returnedAt: Date? = nil,
) async throws -> Loan {
    let loan = Loan(gameID: gameID, memberID: memberID, borrowedAt: borrowedAt, dueAt: dueAt)
    loan.returnedAt = returnedAt
    try await loan.save(on: app.db)
    return loan
}

func registerUser(
    _ app: Application,
    email: String = "camille@example.com",
    password: String = "password"
) async throws -> AuthDTO {
    var user: AuthDTO?
    try await app.test(
        .POST,
        "auth/register",
        beforeRequest:  { req in
            try req.content.encode(
                RegisterDTO(email: email, password: password)
            )
        },
        afterResponse: { res async throws in
            user = try res.content.decode(AuthDTO.self)
        })
    return try XCTUnwrap(user)
}

func registerUserWithExpiredToken(
    _ app: Application,
    email: String = "camille@example.com",
    password: String = "password"
) async throws -> AuthDTO {
    let user = User(email: email, password: password)
    try await user.save(on: app.db)
    var payload = UserPayload(id: user.id!)
    payload.expiration = Date().addingTimeInterval(-24 * 3600)
    let signer = JWTSigner.hs256(key: Environment.get("JWT_KEY")!)
    let jwt = try signer.sign(payload)

    return AuthDTO(
            token: jwt,
            expiresAt: payload.expiration,
            user: user.toDTO()
        )
}
