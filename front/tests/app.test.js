import {
  assertEqual,
  assertIncludes,
  assertTrue,
  test,
  waitFor,
} from "./runner.js";
import { mountApp } from "./helpers.js";

const catan = {
  id: "g1",
  title: "Catan",
  minPlayers: 3,
  maxPlayers: 4,
  durationMinutes: 90,
  isAvailable: true,
};
const dixit = {
  id: "g2",
  title: "Dixit",
  minPlayers: 3,
  maxPlayers: 6,
  durationMinutes: 30,
  isAvailable: false,
};
const sevenWonders = {
  id: "g3",
  title: "Seven Wonders",
  minPlayers: 2,
  maxPlayers: 8,
  durationMinutes: 90,
  isAvailable: false,
};
const camille = { id: "m1", name: "Camille", email: "camille@example.com" };

const catanLoan = {
  id: "l1",
  gameID: "g1",
  memberID: "m1",
  borrowedAt: new Date(),
  dueAt: new Date().setDate(new Date().getDate() + 14),
  returnedAt: new Date().setDate(new Date().getDate() + 7),
};
const dixitLoan = {
  id: "l2",
  gameID: "g2",
  memberID: "m1",
  borrowedAt: new Date(),
  dueAt: new Date().setDate(new Date().getDate() + 14),
};
const returnedDixitLoan = {
  id: "l2",
  gameID: "g2",
  memberID: "m1",
  borrowedAt: new Date(),
  dueAt: new Date().setDate(new Date().getDate() + 14),
  returnedAt: new Date(),
};
const sevenWondersLoan = {
  id: "l3",
  gameID: "g3",
  memberID: "m1",
  borrowedAt: new Date().setDate(new Date().getDate() - 7),
  dueAt: new Date().setDate(new Date().getDate() - 1),
};

const cardOf = (app, title) =>
  app
    .$$("#games-list .card")
    .find((card) => card.querySelector("h3").textContent === title);

// --- Jeux

test("games list shows one card per game with its availability", async () => {
  const app = await mountApp({
    "GET /games": [catan, dixit],
    "GET /loans/overdue": [],
  });
  await waitFor(
    () => app.$$("#games-list .card").length === 2,
    "deux cartes de jeu",
  );
  assertIncludes(cardOf(app, "Catan").textContent, "Disponible");
  assertIncludes(cardOf(app, "Dixit").textContent, "Emprunté");
  assertIncludes(cardOf(app, "Catan").textContent, "3 à 4 joueur·ses · 90 min");
});

test("only an available game offers Borrow", async () => {
  const app = await mountApp({
    "GET /games": [catan, dixit],
    "GET /loans/overdue": [],
  });
  await waitFor(() => app.$$("#games-list .card").length === 2);
  const labels = (title) =>
    [...cardOf(app, title).querySelectorAll("button")].map(
      (button) => button.textContent,
    );
  assertTrue(
    labels("Catan").includes("Emprunter"),
    "Catan devrait proposer Emprunter",
  );
  assertTrue(
    !labels("Dixit").includes("Emprunter"),
    "Dixit est emprunté, il ne doit pas proposer Emprunter",
  );
});

test("with no game, a message invites to add one", async () => {
  const app = await mountApp({ "GET /games": [], "GET /loans/overdue": [] });
  await waitFor(() => !app.$("#games-empty").hidden);
  assertIncludes(app.$("#games-empty").textContent, "ne contient aucun jeu");
  assertIncludes(app.$("#games-empty").textContent, "Ajouter un jeu");
});

test("adding a game posts the form then reloads the list", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "GET /loans/overdue": [],
    "POST /games": [201, { ...catan, id: "g3", title: "Dixit" }],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Ajouter un jeu");
  const form = app.$("#game-form");
  form.elements.title.value = "  Dixit ";
  form.elements.minPlayers.value = "3";
  form.elements.maxPlayers.value = "6";
  form.elements.durationMinutes.value = "30";
  form.requestSubmit();
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "POST" && call.path === "/games",
      ),
    "l'appel POST /games",
  );
  assertEqual(app.calls.find((call) => call.method === "POST").body, {
    title: "Dixit",
    minPlayers: 3,
    maxPlayers: 6,
    durationMinutes: 30,
  });
  await waitFor(() => !app.$("#game-dialog").open, "la boîte se ferme");
});

test("a validation error is shown in French and the dialog stays open", async () => {
  const app = await mountApp({
    "GET /games": [],
    "GET /loans/overdue": [],
    "POST /games": [
      400,
      {
        error: true,
        reason: "title is empty, durationMinutes is less than minimum of 1",
      },
    ],
  });
  await waitFor(() => !app.$("#games-empty").hidden, "la page est chargée");
  app.click("Ajouter un jeu");
  app.$("#game-form").requestSubmit();
  await waitFor(
    () => !app.$("#game-dialog .form-error").hidden,
    "le message d'erreur",
  );
  assertEqual(
    app.$("#game-dialog .form-error").textContent,
    "Le titre est obligatoire. La durée doit être d'au moins 1.",
  );
  assertTrue(app.$("#game-dialog").open, "la boîte devrait rester ouverte");
});

test("deleting a game", async () => {
  let games = [catan];
  const app = await mountApp({
    "GET /games": () => games,
    "GET /loans/overdue": [],
    "DELETE /games/g1": () => {
      games = [];
      return [204];
    },
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Supprimer", cardOf(app, "Catan"));
  await waitFor(
    () => app.$("#delete-game-dialog").open,
    "la boîte de suppression",
  );
  app.$("#delete-game-form").requestSubmit();
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "DELETE" && call.path === "/games/g1",
      ),
    "l'appel DELETE /games",
  );
  await waitFor(
    () => !app.$("#delete-game-dialog").open,
    "la fermeture de la boîte",
  );
  await waitFor(
    () => app.$$("#games-list .card").length === 0,
    // "la suppression de la carte",
    `carte toujours présente. Appels : ${JSON.stringify(app.calls)}`,
  );
});

test("deleting game with loans explains that it cannot be deleted", async () => {
  let games = [catan];
  const app = await mountApp({
    "GET /games": () => games,
    "GET /loans/overdue": [],
    "GET /members": [camille],
    "POST /loans": [
      201,
      {
        id: "l1",
        gameID: "g1",
        memberID: "m1",
        borrowedAt: new Date().toISOString(),
        dueAt: new Date().toISOString(),
      },
    ],
    "DELETE /games/g1": () => {
      games = [catan];
      return [
        409,
        { error: true, reason: "A game with loans cannot be deleted" },
      ];
    },
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Supprimer", cardOf(app, "Catan"));
  await waitFor(
    () => app.$("#delete-game-dialog").open,
    "la boîte de suppression",
  );
  app.$("#delete-game-form").requestSubmit();
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "DELETE" && call.path === "/games/g1",
      ),
    "l'appel DELETE /games",
  );
  await waitFor(
    () => !app.$("#delete-game-dialog .form-error").hidden,
    "le message d'erreur",
  );
  assertIncludes(
    app.$("#delete-game-dialog .form-error").textContent,
    "ce jeu a un historique d'emprunts",
  );
});

test("search game shows one card per game with its availability", async () => {
  const app = await mountApp({
    "GET /games": [catan, dixit],
    "GET /loans/overdue": [],
    "GET /games?q=cat&players=3&maxDuration=80": [catan],
  });
  await waitFor(() => app.$$("#games-list .card").length === 2);
  const form = app.$(".filters");
  form.elements.gameTitle.value = "cat";
  form.elements.players.value = "3";
  form.elements.maxDuration.value = "80";
  app.$(".filters").requestSubmit();
  await waitFor(
    () =>
      app.calls.some(
        (call) =>
          call.method === "GET" &&
          call.path === "/games" &&
          call.search === "?q=cat&players=3&maxDuration=80",
      ),
    "l'appel GET /games?",
  );
  await waitFor(() => app.$$("#games-list .card").length === 1);
  assertIncludes(cardOf(app, "Catan").textContent, "Disponible");
});

test("search game shows empty result", async () => {
  const app = await mountApp({
    "GET /games": [catan, dixit],
    "GET /loans/overdue": [],
    "GET /games?q=unknown&players=30&maxDuration=10": [],
  });
  await waitFor(() => app.$$("#games-list .card").length === 2);
  const form = app.$(".filters");
  form.elements.gameTitle.value = "unknown";
  form.elements.players.value = "30";
  form.elements.maxDuration.value = "10";
  app.$(".filters").requestSubmit();
  await waitFor(
    () =>
      app.calls.some(
        (call) =>
          call.method === "GET" &&
          call.path === "/games" &&
          call.search === "?q=unknown&players=30&maxDuration=10",
      ),
    "l'appel GET /games?",
  );
  await waitFor(() => app.$$("#games-list .card").length === 0);
  assertIncludes(app.$("#query-empty").textContent, "Aucun jeu");
});
// --- Emprunts

test("borrowing a game sends the game and the chosen member", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "GET /loans/overdue": [],
    "GET /members": [camille],
    "POST /loans": [
      201,
      {
        id: "l1",
        gameID: "g1",
        memberID: "m1",
        borrowedAt: new Date().toISOString(),
        dueAt: new Date().toISOString(),
      },
    ],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(() => app.$("#borrow-dialog").open, "la boîte d'emprunt");
  app.$("#borrow-form").requestSubmit();
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "POST" && call.path === "/loans",
      ),
    "l'appel POST /loans",
  );
  assertEqual(app.calls.find((call) => call.path === "/loans").body, {
    gameID: "g1",
    memberID: "m1",
  });
  await waitFor(
    () => app.$("#toasts").textContent.includes("emprunté"),
    "le message de confirmation",
  );
});

test("borrowing without any member explains that one must be added first", async () => {
  const app = await mountApp({
    "GET /games": [catan],
    "GET /loans/overdue": [],
    "GET /members": [],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Emprunter", cardOf(app, "Catan"));
  await waitFor(
    () => app.$("#toasts").textContent.includes("Ajoutez d'abord"),
    "le message d'aide",
  );
  assertTrue(
    !app.$("#borrow-dialog").open,
    "la boîte d'emprunt ne doit pas s'ouvrir",
  );
});

test("return a game return the updated loan", async () => {
  const app = await mountApp({
    "GET /games": [dixit],
    "GET /loans/overdue": [],
    "GET /members": [camille],
    "GET /members/m1/loans": [dixitLoan],
    "POST /loans/l2/return": [returnedDixitLoan],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Rendre", cardOf(app, "Dixit"));
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "POST" && call.path === "/loans/l2/return",
      ),
    "l'appel POST /loans/l2/return",
  );
  await waitFor(
    () => app.$("#toasts").textContent.includes("Le jeu a bien été rendu"),
    "le message de confirmation",
  );
});

test("return a game already returned display error message", async () => {
  const app = await mountApp({
    "GET /games": [dixit],
    "GET /loans/overdue": [],
    "GET /members": [camille],
    "GET /members/m1/loans": [dixitLoan],
    "POST /loans/l2/return": [
      409,
      { error: true, reason: "Loan is already returned" },
    ],
  });
  await waitFor(() => app.$$("#games-list .card").length === 1);
  app.click("Rendre", cardOf(app, "Dixit"));
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "POST" && call.path === "/loans/l2/return",
      ),
    "l'appel POST /loans/l2/return",
  );
  await waitFor(
    () => app.$("#toasts").textContent.includes("déjà été rendu"),
    "le message d'erreur",
  );
});

test("overdue loans tab list the overdue loans", async () => {
  const app = await mountApp(
    {
      "GET /loans/overdue": [sevenWondersLoan],
      "GET /games/g3": sevenWonders,
      "GET /members/m1": camille,
    },
    { hash: "#overdue-loans" },
  );
  await waitFor(() => app.$$("#overdue-loans-list .row").length === 1);
  assertIncludes(
    app.$("#overdue-loans-list .row").textContent,
    "Seven Wonders",
  );
  assertIncludes(app.$("#overdue-loans-list .row").textContent, "Camille");
});

test("with no overdue loans, display an info message", async () => {
  const app = await mountApp(
    {
      "GET /loans/overdue": [],
    },
    { hash: "#overdue-loans" },
  );
  await waitFor(() => !app.$("#overdue-loans-empty").hidden);
  assertIncludes(
    app.$("#overdue-loans-empty").textContent,
    "Aucun emprunt en retard",
  );
});

// --- Adhérent·es

test("members tab lists the members", async () => {
  const app = await mountApp(
    { "GET /members": [camille], "GET /loans/overdue": [] },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  assertIncludes(app.$("#members-list .row").textContent, "Camille");
  assertIncludes(
    app.$("#members-list .row").textContent,
    "camille@example.com",
  );
});

test("with no member, a message invites to add one", async () => {
  const app = await mountApp(
    { "GET /members": [], "GET /loans/overdue": [] },
    { hash: "#members" },
  );
  await waitFor(() => !app.$("#members-empty").hidden);
  assertIncludes(
    app.$("#members-empty").textContent,
    "Ajouter un·e adhérent·e",
  );
});

test("adding a member posts the form", async () => {
  const app = await mountApp(
    {
      "GET /members": [],
      "GET /loans/overdue": [],
      "POST /members": [201, camille],
    },
    { hash: "#members" },
  );
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  const form = app.$("#member-form");
  form.elements.name.value = " Camille ";
  form.elements.email.value = "camille@example.com";
  form.requestSubmit();
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "POST" && call.path === "/members",
      ),
    "l'appel POST /members",
  );
  assertEqual(app.calls.find((call) => call.method === "POST").body, {
    name: "Camille",
    email: "camille@example.com",
  });
});

test("an email already in use is shown in French", async () => {
  const app = await mountApp(
    {
      "GET /members": [],
      "GET /loans/overdue": [],
      "POST /members": [
        409,
        { error: true, reason: "A member with this email already exists" },
      ],
    },
    { hash: "#members" },
  );
  await waitFor(() => !app.$("#members-empty").hidden);
  app.click("Ajouter un·e adhérent·e");
  app.$("#member-form").requestSubmit();
  await waitFor(
    () => !app.$("#member-dialog .form-error").hidden,
    "le message d'erreur",
  );
  assertIncludes(
    app.$("#member-dialog .form-error").textContent,
    "utilise déjà cette adresse e-mail",
  );
});

test("modify a member", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "GET /loans/overdue": [],
      "PUT /members/m1": [
        200,
        { name: "Charles", email: "charles@example.com" },
      ],
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Modifier", cardOf(app, "Camille"));
  await waitFor(
    () => app.$("#update-member-dialog").open,
    "la boîte de modification de membre",
  );
  const form = app.$("#update-member-form");
  form.elements.name.value = " Charles";
  form.elements.email.value = "charles@example.com";
  form.requestSubmit();
  await waitFor(() =>
    app.calls.some(
      (call) => call.method === "PUT" && call.path === "/members/m1",
      "l'appel PUT /members",
    ),
  );
  assertEqual(app.calls.find((call) => call.method === "PUT").body, {
    name: "Charles",
    email: "charles@example.com",
  });
  await waitFor(
    () => !app.$("#update-member-dialog").open,
    "la fermeture de la boîte",
  );
});

test("update a member and an email already in use is shown in French", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "GET /loans/overdue": [],
      "PUT /members/m1": [
        409,
        { error: true, reason: "A member with this email already exists" },
      ],
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Modifier", cardOf(app, "Camille"));
  await waitFor(
    () => app.$("#update-member-dialog").open,
    "la boîte de modification de membre",
  );
  app.$("#update-member-form").requestSubmit();
  await waitFor(
    () => !app.$("#update-member-dialog .form-error").hidden,
    "le message d'erreur",
  );
  assertIncludes(
    app.$("#update-member-dialog .form-error").textContent,
    "utilise déjà cette adresse e-mail",
  );
});

test("list member loans with all status", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "GET /loans/overdue": [],
      "GET /members/m1/loans": [catanLoan, dixitLoan, sevenWondersLoan],
      "GET /games/g1": catan,
      "GET /games/g2": dixit,
      "GET /games/g3": sevenWonders,
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Emprunts", cardOf(app, "Camille"));
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "GET" && call.path === "/games/g1",
      ),
    "1er appel GET /members/g1",
  );
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "GET" && call.path === "/games/g2",
      ),
    "2e appel GET /members/g2",
  );
  await waitFor(
    () =>
      app.calls.some(
        (call) => call.method === "GET" && call.path === "/games/g3",
      ),
    "3e appel GET /members/g3",
  );
  await waitFor(
    () => app.$("#member-loans-dialog").open,
    "la boîte de liste d'emprunts",
  );
  // await waitFor(() => app.$("#member-loans-list").length === 3);
  assertEqual(
    app.$("#member-loans-list").children[0].children[0].children[0].textContent,
    "Catan",
  );
  assertTrue(
    app
      .$("#member-loans-list")
      .children[0].children[0].children[3].textContent.includes("Rendu"),
    "le status de l'emprunt est 'Rendu'",
  );
  assertEqual(
    app.$("#member-loans-list").children[1].children[0].children[0].textContent,
    "Dixit",
  );
  assertTrue(
    app
      .$("#member-loans-list")
      .children[1].children[0].children[3].textContent.includes("En cours"),
    "le status de l'emprunt est 'En cours'",
  );
  assertEqual(
    app.$("#member-loans-list").children[2].children[0].children[0].textContent,
    "Seven Wonders",
  );
  assertTrue(
    app
      .$("#member-loans-list")
      .children[2].children[0].children[3].textContent.includes("En retard"),
    "le status de l'emprunt est 'En retard'",
  );
});

test("with no loans, display an info message", async () => {
  const app = await mountApp(
    {
      "GET /members": [camille],
      "GET /loans/overdue": [],
      "GET /members/m1/loans": [],
    },
    { hash: "#members" },
  );
  await waitFor(() => app.$$("#members-list .row").length === 1);
  app.click("Emprunts", cardOf(app, "Camille"));
  await waitFor(
    () => app.$("#member-loans-dialog").open,
    "la boîte de liste d'emprunts",
  );
  assertIncludes(
    app.$("#member-loans-empty").textContent,
    "n'as pas encore emprunté de jeu",
  );
});
