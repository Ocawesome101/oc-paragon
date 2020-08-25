function build.all()
  for i=1, #build, 1 do
    build[i]()
  end
end
