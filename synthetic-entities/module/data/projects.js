export function projectFixtures() {
    return [
        {
            project_id: "project-1",
            name: "Kubling samples",
            members: [
                {
                    member_id: "user-1",
                    display_name: "Ada",
                    role: "owner"
                },
                {
                    member_id: "user-2",
                    display_name: "Linus",
                    role: "developer"
                }
            ]
        }
    ];
}
