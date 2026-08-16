if (auth.authenticationSource.value() !== "SOCKET_TRANSPORT") {
    auth.bad("This sample accepts Kubling socket-transport authentication only.");
} else if (auth.userName === "reader" && auth.credentials === "reader-pass") {
    auth.addPrincipal(auth.userName);
    auth.addRole("ROLE_TASK_READER");
    auth.trust();
} else if (auth.userName === "editor" && auth.credentials === "editor-pass") {
    auth.addPrincipal(auth.userName);
    auth.addRole("ROLE_TASK_EDITOR");
    auth.trust();
} else {
    auth.bad("Invalid sample credentials.");
}
