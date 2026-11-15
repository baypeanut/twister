import Foundation
import TwisterCore

let token=CancellationToken()
let signals=SignalCancellation(token:token)
exit(signals.exitCode(TwisterCommandLine.run(token:token)))
