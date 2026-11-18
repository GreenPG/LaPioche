import Fluent
import Vapor

struct GameController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        let games = routes.grouped("games")
        let protected = games.grouped(JWTMiddleware())
        protected.get(use: index)
        protected.post(use: create)
        protected.get(":gameID", use: show)
        protected.put(":gameID", use: modify)
        protected.delete(":gameID", use: delete)
    }

    @Sendable
    func index(req: Request) async throws -> [GameDTO] {
        let filters = try req.query.decode(SearchQueryDTO.self)
        let query = Game.query(on: req.db)
        if let title = filters.q {
            query.filter(\.$title ~~ title)
        }
        if let players = filters.players {
            //            guard queryPlayers > 0 else {
            guard players > 0 else {
                throw Abort(.badRequest, reason: "players is less than minimum of 1")
            }
            query.filter(\.$minPlayers <= players)
            query.filter(\.$maxPlayers >= players)
        }
        if let maxDuration = filters.maxDuration {
            guard maxDuration > 0 else {
                throw Abort(.badRequest, reason: "maxDuration is less than minimum of 1")
            }
            query.filter(\.$durationMinutes >= maxDuration)
        }
        var games = try await query
            .with(\.$loans)
            .all()
        if let isAvailable = filters.available {
            if isAvailable {
                games = games.filter({ $0.isAvailable})
            } else {
                games = games.filter({ !$0.isAvailable})
            }
        }
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
