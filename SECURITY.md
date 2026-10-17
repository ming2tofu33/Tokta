# Security

Tokta keeps sign-in sessions for several AI services on your Mac, so security reports matter a lot here.

## Reporting a vulnerability

**Please do not open a public issue.** Report it privately through GitHub instead: go to the repository's **Security** tab and choose **Report a vulnerability**.

Include what you found, how to reproduce it, and which version or commit you tested. You'll get a reply when the maintainer can look at it. This is a personal project, so there is no guaranteed response time.

## What counts

Anything that could expose or misuse a user's sign-in, for example:

- Session cookies, tokens or CLI credentials leaving the Mac, or reaching another app or another account.
- One account's session being used to read or open a different account.
- Data in the iCloud sync containing more than [the README says](README.md#where-your-data-lives).
- Tokta running a command or opening a URL that a service response or web page can control.

A service changing its website or CLI so that usage stops loading is **not** a security issue. Please open a normal issue for that.

## Never share secrets

Don't paste tokens, cookies, `auth.json` contents, real account emails or full API responses into an issue, pull request or report. If a response shape helps, replace every value with a placeholder first.

If you think you shared a secret by accident, sign out of that service or revoke the token first, then tell us.
