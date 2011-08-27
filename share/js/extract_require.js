var detective       = require('detective')

var STDIN           = process.stdin
var STDOUT          = process.stdout



var readInput = function (callback) {
    var input   = ''

    STDIN.resume()
    STDIN.setEncoding('utf8')
    
    STDIN.on('data', function (chunk) {
        input += chunk
    })
    
    STDIN.on('end', function () {
        callback(input)
    })
}


readInput(function (input) {
    
    STDOUT.write(JSON.stringify(detective(input)), 'utf8')
    STDOUT.end()
})
