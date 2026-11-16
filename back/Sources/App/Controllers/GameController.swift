import Fluent
import Vapor

struct GameController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let games = routes.grouped("games")
        games.get(use: index)
        games.post(use: create)
        games.get(":gameID", use: show)
        games.put(":gameID", use: modify)
        games.delete(":gameID", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [GameDTO] {
        let query = Game.query(on: req.db)
        if let queryTitle: String = req.query["q"] {
            query.filter(\.$title ~~ queryTitle)
        }
        if let queryPlayers: Int = req.query["players"] {
            guard queryPlayers > 0 else {
                throw Abort(.badRequest, reason: "players is less than minimum of 1")
            }
            query.filter(\.$minPlayers <= queryPlayers)
            query.filter(\.$maxPlayers >= queryPlayers)
        }
        if let queryDuration: Int = req.query["maxDuration"] {
            guard queryDuration > 0 else {
                throw Abort(.badRequest, reason: "maxDuration is less than minimum of 1")
            }
            query.filter(\.$durationMinutes >= queryDuration)
        }
        let games = try await query
            .with(\.$loans)
            .all()
        return games.map { $0.toDTO() }
    }

    @Sendable
    func create(req: Request) async throws -> Response {
        try CreateGameDTO.validate(content: req)
        let dto = try req.content.decode(CreateGameDTO.self)
        try dto.ensureConsistentPlayerCount()

        let game = dto.toModel()
        try await game.save(on: req.db)
        return try await game.toDTO().encodeResponse(status: .created, for: req)
    }

    @Sendable
    func show(req: Request) async throws -> GameDTO {
        try await findGame(req).toDTO()
    }

    private func findGame(_ req: Request) async throws -> Game {
        guard let gameID = req.parameters.get("gameID", as: UUID.self) else {
            throw Abort(.badRequest, reason: "Invalid game id")
        }
        guard let game = try await Game.query(on: req.db)
            .filter(\.$id == gameID)
            .with(\.$loans)
            .first()
                else {
            throw Abort(.notFound, reason: "Game not found")
        }
        return game
    }

    @Sendable
    func modify(req: Request) async throws -> GameDTO {
        let game = try await findGame(req)

        try ModifyGameDTO.validate(content: req)
        let dto = try req.content.decode(ModifyGameDTO.self)
        try dto.ensureConsistentPlayerCount()
        game.title = dto.title
        game.minPlayers = dto.minPlayers
        game.maxPlayers = dto.maxPlayers
        game.durationMinutes = dto.durationMinutes

        try await game.save(on: req.db)
        return game.toDTO()
    }

    @Sendable
    func delete(req: Request) async throws -> HTTPStatus {
        let game = try await findGame(req)

        let loans = try await Loan.query(on: req.db)
            .filter(\.$game.$id == game.requireID())
            .all()

        guard loans.isEmpty else {
            throw Abort(.conflict, reason: "A game with loans cannot be deleted")
        }

        try await game.delete(on: req.db)
        return .noContent
    }
}
