module.exports = {
    types: [
        { value: 'feat', name: 'feat:     A new feature' },
        { value: 'fix', name: 'fix:      A bug fix' },
        { value: 'docs', name: 'docs:     Documentation only changes' },
        { value: 'style', name: 'style:    Changes that do not affect the meaning of the code' },
        { value: 'refactor', name: 'refactor: A code change that neither fixes a bug nor adds a feature' },
        { value: 'perf', name: 'perf:     A code change that improves performance' },
        { value: 'chore', name: 'chore:    Changes to the build process or auxiliary tools' },
    ],
    scopes: [{ name: 'repo' }, { name: 'web' }, { name: 'api' }, { name: 'ui' }],
    allowCustomScopes: true,
    allowBreakingChanges: ['feat', 'fix'],
    footerPrefix: 'METADATA:',
    appendBranchNameToCommitMessage: false,
    formatCommit: ({ type, scope, subject, body, footer, breaking }) => {
        const isScope = scope ? `(${scope})` : '';
        const header = `${type}${isScope}: ${subject}`;

        let result = header;
        if (body) {
            result += `\n\n${body}`;
        }

        if (breaking) {
            result += `\n\nBREAKING CHANGE:\n${breaking}`;
        }

        const shouldSkipCI = ['docs', 'chore'].includes(type);
        if (footer) {
            result += `\n\n${footer}`;
            if (shouldSkipCI) {
                result += ` [skip ci]`;
            }
        } else if (shouldSkipCI) {
            result += `\n\n[skip ci]`;
        }

        return result;
    }
};
