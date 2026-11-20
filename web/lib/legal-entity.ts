/**
 * Who makes Snapreel, as the website names them (footer, ©, support page, legal pages, structured data, emails).
 *
 * Snapreel is published by an individual, not a company: the Apple Developer Program membership (team N3DBKUVJS5)
 * is enrolled as an Individual, and App Store Connect's legal entity (the seller shown on the App Store) is this
 * name and address. Copied from Apple Developer → Membership details and App Store Connect → Business on
 * 2026-11-20 (Apple stores the street line as "ENAYETPUR, ENAYETPUR, ENAYETPUR"; it's the village, post office and
 * thana, written once here). Keep it identical to docs/legal/*.md, Snapreel/Features/Legal/legal-*.md and
 * AppInfo.publisher in the app. See docs/pro/COMPLIANCE.md.
 *
 * The GitHub org, repo and bundle IDs stay "arclayer"; they aren't the operator's name.
 */
export const LEGAL_ENTITY: {
  name: string;
  addressLines: string[];
  country: string;
  email: "support@snapreel.video";
} = {
  name: "Rezan Ferdous",
  addressLines: ["Enayetpur", "Sirajganj 6751"],
  country: "Bangladesh",
  email: "support@snapreel.video",
};

/** "Enayetpur, Sirajganj 6751, Bangladesh" */
export const LEGAL_ADDRESS = [...LEGAL_ENTITY.addressLines, LEGAL_ENTITY.country].join(", ");
