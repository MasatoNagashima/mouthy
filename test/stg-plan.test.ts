/**
 * @vitest-environment node
 */
import { execFileSync } from "node:child_process";
import { describe, expect, test } from "vitest";

function classify(paths: string): string {
  return execFileSync("bash", ["ci/stg_deploy_plan.sh"], { input: paths, encoding: "utf8" }).trim();
}

describe("STG deploy plan", () => {
  test("rebuilds the API for server and web sources, and ignores the iOS app", () => {
    expect(classify("src/shared/score.ts\nios/Mouthy/App/MouthyApp.swift\n")).toBe("build=1 redeploy=0");
    expect(classify("ios/Mouthy/Features/Home/HomeView.swift\n")).toBe("build=0 redeploy=0");
    expect(classify("docs/stg-setup-owner-checklist.md\ninfra/envs/stg/main.tf\n")).toBe("build=0 redeploy=0");
  });

  test("redeploys without a rebuild when only the deploy script changes", () => {
    expect(classify("ci/stg_deploy.sh\n")).toBe("build=0 redeploy=1");
  });
});
