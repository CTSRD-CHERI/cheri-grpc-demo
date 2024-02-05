
--- Stop the benchmark after a number of messages is exchanged

local counter = 1

function response()
  if counter == 200000 then
    wrk.thread:stop()
  end
  counter = counter + 1
end

-- This script produces output as json

done = function(summary, latency, requests)
  f = io.open("wrk-result.json", "w+")
  f:write("{")

  f:write('"summary": {')
  f:write(string.format('"duration": %d,', summary["duration"]))
  f:write(string.format('"requests": %d,', summary["requests"]))
  f:write(string.format('"bytes": %d', summary["bytes"]))
  f:write("},")

  f:write('"errors": {')
  f:write(string.format('"connect": %d,', summary["errors"]["connect"]))
  f:write(string.format('"read": %d,', summary["errors"]["read"]))
  f:write(string.format('"write": %d,', summary["errors"]["write"]))
  f:write(string.format('"status": %d,', summary["errors"]["status"]))
  f:write(string.format('"timeout": %d', summary["errors"]["timeout"]))
  f:write("},")

  f:write('"latency": {')
  f:write(string.format('"min": %d,', latency.min))
  f:write(string.format('"max": %d,', latency.max))
  f:write(string.format('"mean": %d,', latency.mean))
  f:write(string.format('"std": %d,', latency.stdev))
  f:write(string.format('"percentile50": %d,', latency:percentile(50.0)))
  f:write(string.format('"percentile90": %d,', latency:percentile(90.0)))
  f:write(string.format('"percentile95": %d,', latency:percentile(95.0)))
  f:write(string.format('"percentile99": %d,', latency:percentile(99.0)))
  f:write(string.format('"percentile999": %d', latency:percentile(99.9)))
  f:write("}}")

  f:close()
end
