const packageJson = require('./package.json')

const baseBuild = packageJson.build

module.exports = {
  ...baseBuild,
  artifactName: 'Hermes-Offline-${version}-windows-${arch}.${ext}',
  compression: 'normal',
  extraResources: [
    ...baseBuild.extraResources,
    {
      from: 'build/offline-payload',
      to: 'offline-payload'
    }
  ],
  win: {
    ...baseBuild.win,
    target: ['nsis']
  },
  nsis: {
    ...baseBuild.nsis,
    include: 'build/offline-installer.nsh'
  }
}
