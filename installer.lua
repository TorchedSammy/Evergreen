local core = require 'core'
local command = require 'core.command'
local DocView = require 'core.docview'
local util = require 'plugins.evergreen.util'
local config = require 'plugins.evergreen.config'
local languages = require 'plugins.evergreen.languages'
local highlights = require 'plugins.evergreen.highlights'

local exts = {}

for k, _ in pairs(languages.exts) do
	table.insert(exts, k)
end

local function exec(cmd, opts)
	local proc = process.start(cmd, opts or {})
	if proc then
		while proc:running() do
			coroutine.yield(0.1)
		end
		return (proc:read_stdout() or '<no stdout>\n') .. (proc:read_stderr() or '<no stderr>'), proc:returncode()
	end

	return nil
end

local function compileParser(av, lang)
	local parserDir = util.join {config.parserLocation, lang}
	exec {'git', 'clone', languages.exts[lang], parserDir}

	do
		local out, exitCode = exec({'tree-sitter', 'generate'}, {cwd = parserDir})
		if exitCode ~= 0 then
			core.error('Could not generate parser. Parser install *may* still succeed. Do you have the tree-sitter CLI in your PATH?\nHere are some logs:\n'..out)
		end
	end

	do
		local out, exitCode = exec(PLATFORM == 'Windows' and
		{'cmd', '/c', 'gcc -o parser.so -shared src\\*.c -Os -I.\\src -fPIC'} or
		{'sh', '-c', 'gcc -o parser.so -shared src/*.c -Os -I./src -fPIC'}, {cwd = parserDir})

		if exitCode ~= 0 then
			core.error('An error occured while attempting to compile the parser\n' .. out)
		else
			core.log('Finished installing parser for ' .. lang)
			if getmetatable(av) == DocView and languages.fromDoc(av.doc) == lang then
				highlights.init(av.doc)
				av.doc.highlighter:reset()
			end
		end
	end
end

local function downloadParser(av, lang)
	local url = string.format('https://nightly.link/TorchedSammy/evergreen-builds/workflows/parsers/master/tree-sitter-%s-%s-x86_64.zip', lang, string.lower(PLATFORM))
	local parserDir = util.join {config.parserLocation, lang}
	local parserDest = util.join {parserDir, lang .. '.zip'}

	system.mkdir(parserDir)

	local out, exitCode = exec({'powershell', '-Command', string.format('Invoke-WebRequest -OutFile ( New-Item -Path "%s" -Force ) -Uri %s', parserDest, url)})
	if exitCode ~= 0 then
		core.error('An error occured while attempting to download the parser\n' .. out)
		return
	end

	local out, exitCode = exec({'tar', '-xf', lang .. '.zip'}, {cwd = parserDir})
	if exitCode ~= 0 then
		core.error('An error occured while attempting to download the parser\n' .. out)
		return
	else
		core.log('Finished installing parser for ' .. lang)
		if getmetatable(av) == DocView and languages.fromDoc(av.doc) == lang then
			highlights.init(av.doc)
			av.doc.highlighter:reset()
		end
	end
end

command.add(nil, {
	['evergreen:install'] = function()
		local av = core.active_view

		core.command_view:enter('Install a Treesitter parser for', {
			submit = function(lang)
				if not languages.exts[lang] then
					core.error('Unknown parser for language ' .. lang)
					return
				end
				core.log('Installing parser for ' .. lang)

				core.add_thread(function()
					if PLATFORM == 'Windows' then
						downloadParser(av, lang)
					else
						compileParser(av, lang)
					end
				end)
			end,
			suggest = function()
				return exts
			end
		})
	end
})
