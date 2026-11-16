import { API_URL } from "./config.js";
import { api } from "./api.js";

const $ = (selector, root = document) => root.querySelector(selector);

$("#docs-link").href = API_URL;

const dateFormat = new Intl.DateTimeFormat("fr-FR", { dateStyle: "long" });
const formatDate = (iso) => dateFormat.format(new Date(iso));

// Construit un élément sans jamais passer par innerHTML : les données de
// l'API (titres, noms) sont insérées comme du texte.
function el(tag, props = {}, ...children) {
  const node = document.createElement(tag);
  for (const [key, value] of Object.entries(props)) {
    if (key === "class") node.className = value;
    else if (key.startsWith("on")) node.addEventListener(key.slice(2), value);
    else node.setAttribute(key, value);
  }
  node.append(...children);
  return node;
}

function button(label, onClick, className = "") {
  return el(
    "button",
    { type: "button", class: className, onclick: onClick },
    label,
  );
}

function toast(message, isError = false) {
  const node = el("p", { class: isError ? "toast error" : "toast" }, message);
  $("#toasts").append(node);
  setTimeout(() => node.remove(), 5000);
}

// Exécute une action déclenchée par un bouton et affiche l'erreur de l'API.
async function run(action) {
  try {
    await action();
  } catch (error) {
    toast(error.message, true);
  }
}

function showFormError(dialog, error) {
  const target = $(".form-error", dialog);
  target.textContent = error ? error.message : "";
  target.hidden = !error;
}

for (const cancel of document.querySelectorAll("[data-cancel]")) {
  cancel.addEventListener("click", () => cancel.closest("dialog").close());
}

// Branche un formulaire de boîte de dialogue sur un appel à l'API.
// L'erreur renvoyée par l'API reste affichée dans la boîte, qui ne se ferme
// qu'en cas de succès.
function bindSubmit(dialog, form, handler) {
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    showFormError(dialog, null);
    try {
      await handler(new FormData(form));
      dialog.close();
      await refresh();
    } catch (error) {
      showFormError(dialog, error);
    }
  });
}

// --- Onglets ---------------------------------------------------------------

const tabs = ["games", "members", "overdue-loans"];

function currentTab() {
  const name = location.hash.slice(1);
  return tabs.includes(name) ? name : "games";
}

async function refresh() {
  const tab = currentTab();
  for (const name of tabs) {
    $(`#${name}`).hidden = name !== tab;
    $(`[data-tab="${name}"]`).toggleAttribute("aria-current", name === tab);
  }
  switch (tab) {
    case "games":
      await run(loadGames);
      break;
    case "members":
      await run(loadMembers);
      break;
    case "overdue-loans":
      await run(loadOverdueLoans);
      break;
  }
  const overduedLoans = await api.listOverdueLoans();
  $("#overdue-count").hidden = overduedLoans.length == 0;
  if (overduedLoans.length > 0) {
    $("#overdue-count").textContent = overduedLoans.length;
  }
  // await run(tab === "games" ? loadGames : loadMembers);
}

window.addEventListener("hashchange", refresh);

// --- Jeux ------------------------------------------------------------------

async function loadGames() {
  const games = await api.listGames();
  $("#games-empty").hidden = games.length > 0;
  $("#games-list").replaceChildren(...games.map(gameCard));
}

function gameCard(game) {
  const players =
    game.minPlayers === game.maxPlayers
      ? `${game.minPlayers}`
      : `${game.minPlayers} à ${game.maxPlayers}`;
  const status = game.isAvailable
    ? el("span", { class: "badge ok" }, "Disponible")
    : el("span", { class: "badge busy" }, "Emprunté");

  const actions = el("div", { class: "actions" });
  if (game.isAvailable) {
    actions.append(
      button("Emprunter", () => openBorrowDialog(game), "primary"),
    );
  } else {
    actions.append(button("Rendre", () => returnLoan(game), "primary"));
  }
  actions.append(button("Modifier", () => openModifyDialog(game), "primary"));
  actions.append(
    button("Supprimer", () => openDeleteConfirmationDialog(game), "danger"),
  );

  return el(
    "li",
    { class: "card" },
    el("div", { class: "card-head" }, el("h3", {}, game.title), status),
    el(
      "p",
      { class: "meta" },
      `${players} joueur·ses · ${game.durationMinutes} min`,
    ),
    actions,
  );
}

function openModifyDialog(game) {
  modifiedGame = game;
  modifyGameForm.title.value = game.title;
  modifyGameForm.minPlayers.value = game.minPlayers;
  modifyGameForm.maxPlayers.value = game.maxPlayers;
  modifyGameForm.durationMinutes.value = game.durationMinutes;

  showFormError(modifyGameDialog, null);
  modifyGameDialog.showModal();
}

function openDeleteConfirmationDialog(game) {
  gameToDelete = game;
  deleteGameDialog.querySelector("h2").textContent =
    `Êtes-vous sûr de vouloir supprimer ${game.title} ?`;
  deleteGameDialog.showModal();
}

const gameDialog = $("#game-dialog");
const gameForm = $("#game-form");
const modifyGameDialog = $("#modify-game-dialog");
const modifyGameForm = $("#modify-game-form");
let modifiedGame = null;
const deleteGameDialog = $("#delete-game-dialog");
const deleteGameForm = $("#delete-game-form");
let gameToDelete = null;

$("#add-game").addEventListener("click", () => {
  gameForm.reset();
  showFormError(gameDialog, null);
  gameDialog.showModal();
});

$(".filters").addEventListener("submit", async (event) => {
  event.preventDefault();
  const title = $(".filters").gameTitle.value;
  const players = $(".filters").players.value;
  const maxDuration = $(".filters").maxDuration.value;
  let isFilterValid = true;
  let query = "";
  if (title.length > 0) {
    query += `q=${title}`;
  }
  if (players) {
    [query, isFilterValid] = getNumberQuery(players, query, "players");
  }
  if (maxDuration) {
    [query, isFilterValid] = getNumberQuery(maxDuration, query, "maxDuration");
  }
  if (!isFilterValid) {
    return;
  }
  if (query.length > 0) {
    query = `?${query}`;
  }
  try {
    const games = await api.searchGames(query);
    $("#query-empty").hidden = games.length > 0;
    $("#games-list").replaceChildren(...games.map(gameCard));
  } catch (error) {
    showFormError(dialog, error);
  }
});

function getNumberQuery(input, query, key) {
  let isFilterValid = true;
  if (input > 0 || Number.isInteger(input)) {
    if (query.length > 0) {
      query += `&`;
    }
    query += `${key}=${input}`;
  } else {
    isFilterValid = false;
    const errorString =
      key === "maxDuration" ? "La durée maximal" : "Le nombre de joueur";
    toast(`${errorString} doit être un entier strictement supérieur à 0`);
  }
  return [query, isFilterValid];
}

$("#reset-filter").addEventListener("click", async () => {
  $(".filters").gameTitle.value = "";
  $(".filters").players.value = "";
  $(".filters").maxDuration.value = "";
  await loadGames();
});

bindSubmit(gameDialog, gameForm, (data) =>
  api.createGame({
    title: data.get("title").trim(),
    minPlayers: Number(data.get("minPlayers")),
    maxPlayers: Number(data.get("maxPlayers")),
    durationMinutes: Number(data.get("durationMinutes")),
  }),
);

bindSubmit(modifyGameDialog, modifyGameForm, (data) =>
  api.modifyGame(modifiedGame.id, {
    title: data.get("title").trim(),
    minPlayers: Number(data.get("minPlayers")),
    maxPlayers: Number(data.get("maxPlayers")),
    durationMinutes: Number(data.get("durationMinutes")),
  }),
);

bindSubmit(deleteGameDialog, deleteGameForm, () =>
  api.deleteGame(gameToDelete.id),
);

// --- Emprunts --------------------------------------------------------------

async function loadOverdueLoans() {
  const overduedLoans = await api.listOverdueLoans();
  $("#overdue-loans-empty").hidden = overduedLoans.length > 0;
  $("#overdue-loans-list").replaceChildren(
    ...(await Promise.all(overduedLoans.map(overdueRow))),
  );
}

async function overdueRow(loan) {
  const game = await api.getGame(loan.gameID);
  const member = await api.getMember(loan.memberID);
  const dateFormatOptions = {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  };
  const daysOfDelay = new Date().getDate() - new Date(loan.dueAt).getDate();
  return el(
    "li",
    { class: "row" },
    el(
      "div",
      { class: "row-main" },
      el("strong", {}, game.title),
      el("p", {}, `Emprunté par: ${member.name}`),
      el(
        "p",
        {},
        `Retour prévu le: ${new Date(loan.dueAt).toLocaleString("fr-FR", dateFormatOptions)}`,
      ),
      el("p", { class: "badge late" }, `Jours de retard: ${daysOfDelay}`),
    ),
  );
}

const borrowDialog = $("#borrow-dialog");
const borrowForm = $("#borrow-form");
let borrowedGame = null;

async function openBorrowDialog(game) {
  await run(async () => {
    const members = await api.listMembers();
    if (members.length === 0) {
      toast("Ajoutez d'abord un·e adhérent·e pour pouvoir emprunter.", true);
      return;
    }
    borrowedGame = game;
    $("#borrow-dialog-title").textContent = `Emprunter « ${game.title} »`;
    $("select", borrowForm).replaceChildren(
      ...members.map((member) =>
        el("option", { value: member.id }, `${member.name} (${member.email})`),
      ),
    );
    showFormError(borrowDialog, null);
    borrowDialog.showModal();
  });
}

bindSubmit(borrowDialog, borrowForm, async (data) => {
  const loan = await api.borrow(borrowedGame.id, data.get("memberID"));
  toast(
    `« ${borrowedGame.title} » emprunté, à rendre avant le ${formatDate(loan.dueAt)}.`,
  );
});

async function returnLoan(game) {
  const loanID = await findLoanID(game.id);
  try {
    let loan = await api.returnLoan(loanID);
    toast(`Le jeu a bien été rendu`);
    refresh();
  } catch (error) {
    toast(error.message, true);
  }
}

async function findLoanID(gameID) {
  let members = await api.listMembers();
  for (const member of members) {
    const memberLoans = await api.listMemberLoans(member.id);
    for (const loan of memberLoans) {
      if (loan.gameID === gameID && !("returnedAt" in loan)) {
        return loan.id;
      }
    }
  }
}

// --- Adhérent·es -----------------------------------------------------------

async function loadMembers() {
  const members = await api.listMembers();
  $("#members-empty").hidden = members.length > 0;
  $("#members-list").replaceChildren(...members.map(memberRow));
}

async function loadMemberLoans(member) {
  const loans = await api.listMemberLoans(member.id);
  if (loans.length > 0) {
    $("#member-loans-empty").hidden = true;
    $("#member-loans-list").replaceChildren(
      ...(await Promise.all(loans.map(memberLoansRow))),
    );
  } else {
    $("#member-loans-list").textContent = "";
    $("#member-loans-empty").hidden = false;
    $("#member-loans-empty").textContent =
      `${member.name} n'as pas encore emprunté de jeu`;
  }
}

function memberRow(member) {
  const actions = el("div", { class: "actions" });
  actions.append(
    button("Emprunts", () => openMemberLoansDialog(member), "primary"),
  );
  actions.append(
    button("Modifier", () => openUpdateMemberDialog(member), "primary"),
  );
  actions.append(
    button("Supprimer", () => openDeleteMemberDialog(member), "danger"),
  );
  return el(
    "li",
    { class: "row" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, member.name)),
      el("p", { class: "meta" }, member.email),
    ),
    actions,
  );
}

async function memberLoansRow(loan) {
  const game = await api.getGame(loan.gameID);
  let status;
  if (loan.returnedAt) {
    status = "Rendu";
  } else if (
    new Date().setHours(0, 0, 0, 0) > new Date(loan.dueAt).setHours(0, 0, 0, 0)
  ) {
    status = "En retard";
  } else {
    status = "En cours";
  }
  const dateFormatOptions = {
    weekday: "long",
    year: "numeric",
    month: "long",
    day: "numeric",
  };
  return el(
    "li",
    { class: "row" },
    el(
      "div",
      { class: "row-main" },
      el("p", {}, el("strong", {}, game.title)),
      el(
        "p",
        { class: "meta" },
        `Emprunté le: ${new Date(loan.borrowedAt).toLocaleString("fr-FR", dateFormatOptions)}`,
      ),
      el(
        "p",
        { class: "meta" },
        `A rendre le: ${new Date(loan.dueAt).toLocaleString("fr-FR", dateFormatOptions)}`,
      ),
      el("p", { class: "meta" }, `Status: ${status}`),
    ),
  );
}

const memberDialog = $("#member-dialog");
const memberForm = $("#member-form");
const memberUpdateDialog = $("#update-member-dialog");
const memberUpdateForm = $("#update-member-form");
const memberDeleteDialog = $("#delete-member-dialog");
const memberDeleteForm = $("#delete-member-form");
const memberLoansDialog = $("#member-loans-dialog");
let updatedMember = null;
let memberToDelete = null;

function openUpdateMemberDialog(member) {
  updatedMember = member;
  memberUpdateForm.name.value = member.name;
  memberUpdateForm.email.value = member.email;

  showFormError(memberUpdateDialog, null);
  memberUpdateDialog.showModal();
}

function openDeleteMemberDialog(member) {
  memberToDelete = member;
  showFormError(memberDeleteDialog, null);
  memberDeleteDialog.showModal();
}

async function openMemberLoansDialog(member) {
  await loadMemberLoans(member);
  memberLoansDialog.showModal();
}

$("#add-member").addEventListener("click", () => {
  memberForm.reset();
  showFormError(memberDialog, null);
  memberDialog.showModal();
});

bindSubmit(memberDialog, memberForm, (data) =>
  api.createMember({
    name: data.get("name").trim(),
    email: data.get("email").trim(),
  }),
);

bindSubmit(memberUpdateDialog, memberUpdateForm, (data) =>
  api.updateMember(updatedMember.id, {
    name: data.get("name").trim(),
    email: data.get("email").trim(),
  }),
);

bindSubmit(memberDeleteDialog, memberDeleteForm, () =>
  api.deleteMember(memberToDelete.id),
);

refresh();
