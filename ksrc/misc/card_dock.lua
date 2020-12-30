-- automatic card dock support --

do
  for k, v in component.list("carddock") do
    component.invoke(k, "bindComponent")
  end
  k.evt.register("component_added", function(_, a, t)
    if t == "carddock" then
      component.invoke(a, "bindComponent")
    end
  end)
end
