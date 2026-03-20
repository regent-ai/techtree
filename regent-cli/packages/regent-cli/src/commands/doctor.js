import { runDoctor, runFullDoctor, runScopedDoctor } from "@regent/runtime";
import { getBooleanFlag, getFlag, parseIntegerFlag } from "../parse.js";
import { printJson, printText } from "../printer.js";
import { renderDoctorReport } from "../printers/doctorPrinter.js";
const DOCTOR_SCOPES = new Set(["runtime", "auth", "techtree", "transports", "xmtp"]);
const reportHasInternalFailure = (report) => {
    return report.checks.some((check) => check.details?.internal === true);
};
const doctorExitCode = (report) => {
    if (reportHasInternalFailure(report)) {
        return 3;
    }
    return report.summary.fail > 0 ? 1 : 0;
};
export class CliUsageError extends Error {
    constructor(message) {
        super(message);
        this.name = "CliUsageError";
    }
}
export async function runDoctorCommand(args, configPath) {
    const scopeCandidate = args.positionals[1];
    const scope = scopeCandidate && DOCTOR_SCOPES.has(scopeCandidate)
        ? scopeCandidate
        : undefined;
    if (scopeCandidate && !scope && !scopeCandidate.startsWith("--")) {
        throw new CliUsageError(`invalid doctor scope: ${scopeCandidate}`);
    }
    const json = getBooleanFlag(args, "json");
    const verbose = getBooleanFlag(args, "verbose");
    const fix = getBooleanFlag(args, "fix");
    const full = getBooleanFlag(args, "full");
    const quiet = getBooleanFlag(args, "quiet");
    const onlyFailures = getBooleanFlag(args, "only-failures");
    const ci = getBooleanFlag(args, "ci");
    if (scope && full) {
        throw new CliUsageError("`regent doctor --full` does not support scoped subcommands");
    }
    const knownParentId = parseIntegerFlag(args, "known-parent-id");
    const cleanupCommentBodyPrefix = getFlag(args, "cleanup-comment-body-prefix");
    const report = full
        ? await runFullDoctor({
            json,
            verbose,
            fix,
            knownParentId,
            cleanupCommentBodyPrefix,
        }, { configPath })
        : scope
            ? await runScopedDoctor({
                scope,
                json,
                verbose,
                fix,
            }, { configPath })
            : await runDoctor({
                json,
                verbose,
                fix,
            }, { configPath });
    if (json) {
        printJson(report);
    }
    else {
        printText(renderDoctorReport(report, { verbose, quiet, onlyFailures, ci }));
    }
    return doctorExitCode(report);
}
//# sourceMappingURL=doctor.js.map
