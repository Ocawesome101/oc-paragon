function build.all()
  log("Executing build")
  for i=1, #build, 1 do
    build[i]()
  end
end
