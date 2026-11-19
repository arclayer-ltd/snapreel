// GET /api/health: whether the relay has its APNs settings (never shows them).
export default function handler(req, res) {
  const configured = Boolean(process.env.APNS_KEY_ID && process.env.APNS_TEAM_ID && process.env.APNS_KEY_P8);
  res.status(200).json({ ok: true, configured });
}
