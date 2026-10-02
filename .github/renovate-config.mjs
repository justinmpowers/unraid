/**
 * Self-hosted (global) Renovate config.
 *
 * renovatebot/github-action bind-mounts this file into the Renovate container
 * and points RENOVATE_CONFIG_FILE at it. It holds only the settings that need
 * credentials from the environment; repo policy (managers, grouping, labels)
 * stays in renovate.json.
 *
 * Credentials are read from process.env rather than interpolated into a JSON
 * string, so a password containing a quote or backslash cannot break parsing.
 *
 * Every variable read here must also be listed in the workflow's
 * `additional-env-list`, or the action will not pass it into the container.
 */

const hostRules = [];

function dockerLogin(matchHost, username, password) {
  if (!username || !password) {
    console.warn(
      `renovate-config: no credentials for ${matchHost}, using anonymous access`,
    );
    return;
  }
  hostRules.push({ hostType: 'docker', matchHost, username, password });
}

// Anonymous Docker Hub pulls are rate limited per IP, and the self-hosted
// runner shares its IP with everything else on the box. Most images we track
// live here, so this login is the one that actually matters.
dockerLogin(
  'docker.io',
  process.env.DOCKER_HUB_USERNAME,
  process.env.DOCKER_HUB_PASSWORD,
);

// Optional. The ghcr.io images we track (the obico ones) are public, so this
// only buys a higher rate limit. Set GHCR_USERNAME to a GitHub username and
// GHCR_TOKEN to a PAT with `read:packages` to enable it.
dockerLogin('ghcr.io', process.env.GHCR_USERNAME, process.env.GHCR_TOKEN);

// docker.n8n.io is a public mirror with no credentials to supply.

export default { hostRules };
