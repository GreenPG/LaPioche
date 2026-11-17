import { api, ApiError, translateError } from "../api.js";
import { assertEqual, assertIncludes, assertTrue, test } from "./runner.js";
import { fakeApi, withFakeFetch } from "./helpers.js";

// --- translateError : les messages de l'API deviennent des phrases en français

test("translateError translates a known message", () => {
  assertEqual(
    translateError(409, "Game is already on loan"),
    "Ce jeu est déjà emprunté : il faut d'abord le rendre.",
  );
});

test("translateError translates each validation error separately", () => {
  const message = translateError(
    400,
    "title is empty, minPlayers is less than minimum of 1",
  );
  assertEqual(
    message,
    "Le titre est obligatoire. Le nombre minimum de joueur·ses doit être d'au moins 1.",
  );
});

test("translateError translates a missing field and an invalid email", () => {
  assertEqual(
    translateError(400, "name is required"),
    "Le nom est obligatoire.",
  );
  assertIncludes(
    translateError(400, "email is not a valid email address"),
    "adresse e-mail n'est pas valide",
  );
});

test("translateError never lets unknown English through", () => {
  assertEqual(
    translateError(409, "Something unexpected"),
    "Cette action est impossible dans l'état actuel des données.",
  );
  assertEqual(
    translateError(500, "boom"),
    "Le serveur a rencontré une erreur. Réessayez dans un instant.",
  );
  assertEqual(
    translateError(418, "teapot"),
    "Une erreur est survenue. Réessayez.",
  );
});

// --- requêtes envoyées à l'API

test("listGames calls GET /games", async () => {
  const { fetch, calls } = fakeApi({ "GET /games": [] });
  await withFakeFetch(fetch, () => api.listGames());
  assertEqual(`${calls[0].method} ${calls[0].path}`, "GET /games");
});

test("createGame sends a JSON POST", async () => {
  const { fetch, calls } = fakeApi({ "POST /games": [201, { id: "1" }] });
  const game = {
    title: "Catan",
    minPlayers: 3,
    maxPlayers: 4,
    durationMinutes: 90,
  };
  const created = await withFakeFetch(fetch, () => api.createGame(game));
  assertEqual(calls[0].method, "POST");
  assertEqual(calls[0].body, game);
  assertEqual(created.id, "1");
});

test("borrow sends the game and the member", async () => {
  const { fetch, calls } = fakeApi({ "POST /loans": [201, { id: "l1" }] });
  await withFakeFetch(fetch, () => api.borrow("g1", "m1"));
  assertEqual(calls[0].body, { gameID: "g1", memberID: "m1" });
});

test("getMember calls GET /members/:id", async () => {
  const { fetch, calls } = fakeApi({
    "GET /members/m1": [
      200,
      { id: "1", name: "Camille", email: "camille@example.com" },
    ],
  });
  let member = await withFakeFetch(fetch, () => api.getMember("m1"));
  assertEqual(calls[0].method, "GET");
  assertEqual(member.id, "1");
});

test("listOverdueLoans calls GET /loans/overdue", async () => {
  const loans = [
    {
      id: 1,
      gameID: 1,
      memberID: 1,
      borrowedAt: "2026-11-10T00:00:00Z",
      dueAt: "2026-11-24T00:00:00Z",
    },
  ];
  const { fetch, calls } = fakeApi({
    "GET /loans/overdue": loans,
  });
  let data = await withFakeFetch(fetch, () => api.listOverdueLoans());
  assertEqual(calls[0].method, "GET");
  assertEqual(data, loans);
});

test("searchGames calls GET /games?q=title&players=numberPlayers&maxDuration=maxDuration", async () => {
  const { fetch, calls } = fakeApi({
    "GET /games?q=g1&players=4&maxDuration=60": [],
  });
  await withFakeFetch(fetch, () =>
    api.searchGames("?q=g1&players=4&maxDuration=60"),
  );
  assertEqual(`${calls[0].method} ${calls[0].path}`, "GET /games");
  assertEqual(`${calls[0].search}`, "?q=g1&players=4&maxDuration=60");
});

test("modifyGame calls PUT /games/:id", async () => {
  const { fetch, calls } = fakeApi({
    "PUT /games/1": [
      200,
      {
        id: 1,
        title: "Catan",
        minPlayers: 3,
        maxPlayers: 4,
        durationMinutes: 80,
        isAvailable: true,
      },
    ],
  });
  const game = {
    title: "Catan",
    minPlayers: 3,
    maxPlayers: 4,
    durationMinutes: 80,
  };
  const modified = await withFakeFetch(fetch, () => api.modifyGame(1, game));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "PUT /games/1");
  assertEqual(calls[0].body, game);
  assertEqual(modified.id, 1);
});

test("deleteGame calls DELETE /games/:id", async () => {
  const { fetch, calls } = fakeApi({
    "DELETE /games/1": [204],
  });
  await withFakeFetch(fetch, () => api.deleteGame(1));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "DELETE /games/1");
});

test("getGame calls GET /games/:id", async () => {
  const { fetch, calls } = fakeApi({
    "GET /games/1": [
      200,
      {
        id: 1,
        title: "Catan",
        minPlayers: 3,
        maxPlayers: 4,
        durationMinutes: 80,
        isAvailable: true,
      },
    ],
  });
  const game = await withFakeFetch(fetch, () => api.getGame(1));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "GET /games/1");
  assertEqual(game.id, 1);
});

test("listMembers calls GET /members", async () => {
  const { fetch, calls } = fakeApi({
    "GET /members": [
      {
        id: 1,
        name: "Camille",
        email: "camille@example.com",
      },
    ],
  });
  const members = await withFakeFetch(fetch, () => api.listMembers());
  assertEqual(`${calls[0].method} ${calls[0].path}`, "GET /members");
  assertEqual(members.length, 1);
  assertEqual(members[0].id, 1);
});

test("listMemberLoans GET /member/:id/loans", async () => {
  const { fetch, calls } = fakeApi({
    "GET /members/1/loans": [
      {
        id: 1,
        gameID: 1,
        member: 1,
        borrowedAt: Date(),
        dueAt: Date(),
        returnedAt: Date(),
      },
    ],
  });
  const loans = await withFakeFetch(fetch, () => api.listMemberLoans(1));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "GET /members/1/loans");
  assertEqual(loans.length, 1);
  assertEqual(loans[0].id, 1);
});

test("createMember calls POST /members", async () => {
  const { fetch, calls } = fakeApi({
    "POST /members": [
      201,
      { id: 1, name: "camille", email: "camille@example.com" },
    ],
  });
  const member = {
    name: "camille",
    email: "camille@example.com",
  };
  const created = await withFakeFetch(fetch, () => api.createMember(member));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "POST /members");
  assertEqual(created.id, 1);
});

test("updateMember calls PUT /members/:id", async () => {
  const { fetch, calls } = fakeApi({
    "PUT /members/1": { id: 1, name: "Camille", email: "camille@example.com" },
  });
  const member = {
    name: "camille",
    email: "camille@example.com",
  };
  const updated = await withFakeFetch(fetch, () => api.updateMember(1, member));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "PUT /members/1");
  assertEqual(updated.id, 1);
});

test("deleteMember calls DELETE /members/:id", async () => {
  const { fetch, calls } = fakeApi({
    "DELETE /members/1": [204],
  });
  await withFakeFetch(fetch, () => api.deleteMember(1));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "DELETE /members/1");
});

test("returnLoan calls POST /loans/:id/return", async () => {
  const { fetch, calls } = fakeApi({
    "POST /loans/1/return": [
      200,
      {
        id: 1,
        gameID: 1,
        memberID: 1,
        borrowedAt: Date(),
        dueAt: Date(),
        returnedAt: Date(),
      },
    ],
  });
  const loan = await withFakeFetch(fetch, () => api.returnLoan(1));
  assertEqual(`${calls[0].method} ${calls[0].path}`, "POST /loans/1/return");
  assertEqual(loan.id, 1);
});

// --- erreurs

// Attend qu'une promesse échoue et renvoie l'erreur (échoue si elle réussit).
async function expectError(promise) {
  try {
    await promise;
  } catch (error) {
    return error;
  }
  throw new Error("une erreur était attendue");
}

test("an unreachable server gives a clear message", async () => {
  const unreachable = async () => {
    throw new TypeError("Failed to fetch");
  };
  const error = await expectError(
    withFakeFetch(unreachable, () => api.listGames()),
  );
  assertEqual(error.status, 0);
  assertIncludes(error.message, "Impossible de joindre le serveur");
});

test("a game already on loan (409) gives a French message", async () => {
  const { fetch } = fakeApi({
    "POST /loans": [409, { error: true, reason: "Game is already on loan" }],
  });
  const error = await expectError(
    withFakeFetch(fetch, () => api.borrow("g1", "m1")),
  );
  assertTrue(error instanceof ApiError, "l'erreur devrait être une ApiError");
  assertEqual(error.status, 409);
  assertEqual(
    error.message,
    "Ce jeu est déjà emprunté : il faut d'abord le rendre.",
  );
});
