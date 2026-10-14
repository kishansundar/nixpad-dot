-- Yazi's own Entity:icon with one change: icons take the accent (the style of the path at the top), not their fixed colours.
function Entity:icon()
	local icon = th.icon:match(self._file, { hovered = self._file.is_hovered })
	if not icon then
		return ""
	elseif self._file.is_hovered then
		return icon.text .. " "
	else
		return ui.Line(icon.text .. " "):style(th.mgr.cwd)
	end
end
