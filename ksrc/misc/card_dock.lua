-- automatic card dock support --

do
  local _CD_TYPE = "carddock"
  for k, v in component.list(_CD_TYPE) do
    component.invoke(k, "bindComponent")
  end
  k.evt.register("component_added", function(_, a, t)
    if t == _CD_TYPE then
      component.invoke(a, "bindComponent")
    end
  end)
end
