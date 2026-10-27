# Cloudflare Security Audit Skill for Antigravity

This guide covers setup and execution steps for using the Cloudflare Security Audit skill within **Antigravity**.

---

## 1. Installation

1. Create a workspace instructions directory in your repository:
   ```bash
   mkdir -p .antigravity/skills/security-audit
   ```
2. Copy the Cloudflare Security Audit skill files (`SKILL.md` and related context documents) into `.antigravity/skills/security-audit/`:
   ```bash
   git clone https://github.com/cloudflare/security-audit-skill.git /tmp/cf-skill
   cp -r /tmp/cf-skill/skills/security-audit/* .antigravity/skills/security-audit/
   rm -rf /tmp/cf-skill
   ```
3. *(Optional)* If your project uses an `antigravity.json` configuration file, register the skill path in your configuration:
   ```json
   {
     "skills": [
       ".antigravity/skills/security-audit/SKILL.md"
     ]
   }
   ```

---

## 2. Running the Audit

1. Launch the Antigravity workspace panel or agent assistant.
2. Direct the agent to execute the audit using the mounted rules.

**Example Prompts:**
* `"Initiate a security audit using the context provided in .antigravity/skills/security-audit/SKILL.md."`
* `"Audit our API routes and middleware for common vulnerability classes per the local security-audit skill."`

---

## 3. Team Sharing Checklist

1. Commit `.antigravity/skills/` and your `antigravity.json` (if used) to your version control system.
2. Team members pulling the repository will immediately inherit the security auditing rules within their workspace.