//===----------------------------------------------------------------------===//
//
// This source file is part of the Hummingbird server framework project
//
// Copyright (c) 2023 the Hummingbird authors
// Licensed under Apache License v2.0
//
// See LICENSE.txt for license information
// See hummingbird/CONTRIBUTORS.txt for the list of Hummingbird authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import FluentKit
import Foundation
import Hummingbird
import HummingbirdAuth
import HummingbirdBasicAuth
import HummingbirdFluent
import JWTKit
import NIO

struct UserController {
    typealias Context = AppRequestContext
    let jwtKeyCollection: JWTKeyCollection
    let kid: JWKIdentifier
    let fluent: Fluent

    /// Add routes for user controller
    func addRoutes(to group: RouterGroup<Context>) {
        group.put(use: self.create)
        group.group("login").add(
            middleware: BasicAuthenticator { username, _ in
                try await User.query(on: self.fluent.db())
                    .filter(\.$name == username)
                    .first()
            }
        )
        .post(use: self.login)
    }

    /// Create new user
    @Sendable func create(
        _ request: Request,
        context: Context
    ) async throws -> EditedResponse<UserResponse> {
        let createUser = try await request.decode(
            as: CreateUserRequest.self,
            context: context
        )
        let db = self.fluent.db()
        // check if user exists and if they don't then add new user
        let existingUser = try await User.query(on: db)
            .filter(\.$name == createUser.name)
            .first()
        // if user already exist throw conflict
        guard existingUser == nil else { throw HTTPError(.conflict) }

        let user = try await User(from: createUser)
        try await user.save(on: db)

        return .init(status: .created, response: UserResponse(from: user))
    }

    /// Login user and return JWT
    @Sendable func login(_ request: Request, context: Context) async throws -> [String: String] {
        // get authenticated user and return
        guard let user = context.identity else { throw HTTPError(.unauthorized) }
        let payload = JWTPayloadData(
            subject: .init(value: try user.requireID().uuidString),
            expiration: .init(value: Date(timeIntervalSinceNow: 12 * 60 * 60)),
            userName: user.name
        )
        return try await [
            "token": self.jwtKeyCollection.sign(payload, kid: self.kid)
        ]
    }
}
