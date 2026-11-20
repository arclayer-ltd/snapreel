// GET /.well-known/apple-app-site-association: universal links for shared videos (snapreel.video/v/… opens the
// owner's own recording in the app) and shared web credentials. Served as application/json with no redirect.
const APP_ID = "N3DBKUVJS5.co.arclayer.snapreel";

const association = {
  applinks: {
    details: [
      {
        appIDs: [APP_ID],
        components: [{ "/": "/v/*", comment: "Shared Snapreel videos" }],
      },
    ],
  },
  webcredentials: { apps: [APP_ID] },
};

export function GET(): Response {
  return new Response(JSON.stringify(association), {
    headers: { "content-type": "application/json", "cache-control": "public, max-age=3600" },
  });
}
