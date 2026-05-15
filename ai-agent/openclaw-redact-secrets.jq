walk(
  if type == "object" then
    with_entries(
      if .key | test("Token$|^token$|[Aa][Pp][Ii].?[Kk]ey$|[Ss]ecret$|[Aa]llow[Ff]rom$") then
        if   (.value | type == "string") then .value = "***REDACTED***"
        elif (.value | type == "array")  then .value = ["***REDACTED***"]
        else .
        end
      else .
      end
    )
  else .
  end
)
