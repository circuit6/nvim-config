-- ~/.config/nvim/lua/todo_workflow.lua

local M = {} -- This table will hold all our public functions

-- Helper function to get current date formatted as DD.MM.YYYY
function M.get_current_date_header()
    local date_str = vim.fn.strftime("%d.%m.%Y")
    return "## " .. date_str
end

-- Helper to find the line number of a section (e.g., "## Todos" or "## 28.06.2025")
-- Returns line_num (0-indexed) or nil if not found
function M.find_section_line(buffer_lines, section_header)
    for i, line in ipairs(buffer_lines) do
        if line:match("^" .. section_header .. "$") then
            return i - 1 -- Return 0-indexed line number
        end
    end
    return nil
end

--- Ensures consistent spacing around ## headers.
--- Each ## header should have one empty line above it and one below it.
function M.clean_up_structure()
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines
    local lines_to_write = {}
    local line_count = #buffer_lines

    for i = 1, line_count do
        local current_line = buffer_lines[i]
        local prev_line = buffer_lines[i - 1] or ""
        local next_line = buffer_lines[i + 1] or ""

        if current_line:match("^##%s.*") then -- Found a ## header
            -- Add empty line above if not already present and not the very first line
            if i > 1 and prev_line ~= "" then
                table.insert(lines_to_write, "")
            end

            table.insert(lines_to_write, current_line)

            -- Add empty line below if not already present and not the very last line
            if i < line_count and next_line ~= "" then
                table.insert(lines_to_write, "")
            end
        elseif current_line == "" and (prev_line == "" or next_line == "") then
            -- Skip extra empty lines:
            -- If current line is empty and previous line is also empty, skip current (unless it's a header spacing)
            -- If current line is empty and next line is empty, skip current (unless it's a header spacing)
            -- This logic prevents multiple consecutive empty lines, while still allowing header spacing.
            local prev_is_header = prev_line:match("^##%s.*")
            local next_is_header = next_line:match("^##%s.*")
            local prev_is_empty = prev_line == ""
            local next_is_empty = next_line == ""

            if not ((prev_is_header and not next_is_empty) or (next_is_header and not prev_is_empty)) then
                 if (prev_is_empty and not prev_is_header) or (next_is_empty and not next_is_header) then
                    -- This empty line is redundant, skip it
                 else
                    table.insert(lines_to_write, current_line)
                 end
            else
                table.insert(lines_to_write, current_line)
            end
        else
            table.insert(lines_to_write, current_line)
        end
    end

    -- Remove any trailing empty lines if they are not part of header spacing
    while #lines_to_write > 0 and lines_to_write[#lines_to_write] == "" and
          not lines_to_write[#lines_to_write - 1]:match("^##%s.*") do
        table.remove(lines_to_write)
    end

    vim.api.nvim_buf_set_lines(0, 0, -1, false, lines_to_write)
    print("Buffer structure cleaned up!")
end


-- Function to handle finishing a todo item ("xx")
function M.finish_todo_item()
    local original_cursor_pos = vim.api.nvim_win_get_cursor(0) -- Get original cursor position
    local current_line_num = original_cursor_pos[1] - 1 -- 0-indexed line
    local current_col_num = original_cursor_pos[2]
    local current_line = vim.api.nvim_get_current_line()

    -- 1. Check if the current line is an uncompleted task
    if not current_line:match("^%s*%[%s*%]%s.*") then
        print("Not an uncompleted task. Cursor must be on a '[ ]' item.")
        return
    end

    -- 2. Mark as completed and store it
    local completed_task_line = current_line:gsub("%[%s*%]", "[x]")
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines

    -- 3. Remove the task from its current position
    table.remove(buffer_lines, current_line_num + 1) -- Lua tables are 1-indexed

    -- 4. Find or create the ## <Current Date> section
    local date_header = M.get_current_date_header()
    local date_section_line_num = M.find_section_line(buffer_lines, date_header)

    if not date_section_line_num then
        -- Date section doesn't exist, create it above "## Todos" or at the end
        local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")
        local insert_pos

        if todos_section_line_num then
            -- Insert above ## Todos section (or before "## Todos" content starts)
            insert_pos = todos_section_line_num
        else
            -- No ## Todos, insert at the end of the file (or after # Todo Timothy if it's the only one)
            insert_pos = 0 -- Default to top if no headers.
            for i = #buffer_lines, 1, -1 do
                if buffer_lines[i]:match("^#%#?%s.*") then -- Find the last header
                    insert_pos = i
                    break
                end
            end
        end

        -- Insert header, empty line, and the task
        table.insert(buffer_lines, insert_pos + 1, date_header)
        table.insert(buffer_lines, insert_pos + 2, "") -- Add an empty line for spacing
        table.insert(buffer_lines, insert_pos + 3, completed_task_line)
    else
        -- Date section exists, insert the task below it
        local insert_pos = date_section_line_num + 1 -- Start searching from here (after the date header)
        while insert_pos < #buffer_lines and not buffer_lines[insert_pos + 1]:match("^##%s.*") do
            insert_pos = insert_pos + 1
        end
        table.insert(buffer_lines, insert_pos + 1, completed_task_line)
    end

    -- 5. Update the buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

    M.clean_up_structure() -- Call cleanup after modifications

    -- Restore cursor position (adjust for line removal)
    local new_line_count = vim.api.nvim_buf_line_count(0)
    local new_cursor_line = math.min(current_line_num + 1, new_line_count) -- Adjust for removal
    if new_cursor_line == 0 and new_line_count > 0 then new_cursor_line = 1 end -- Ensure cursor is at least on line 1 if file is not empty

    -- If the line was removed and it was the last line, move cursor to the new last line
    -- Otherwise, try to stay on the same line number (which will be a different line now)
    -- or the line above if the original line was removed.
    local line_at_new_pos = vim.api.nvim_buf_get_lines(0, new_cursor_line - 1, new_cursor_line, false)[1] or ""
    local new_cursor_col = math.min(current_col_num, #line_at_new_pos)
    vim.api.nvim_win_set_cursor(0, {new_cursor_line, new_cursor_col})

    print("Task finished and moved!")
end

-- Function to handle creating a new todo item ("ni")
function M.new_todo_item()
    local buffer_lines = vim.api.nvim_buf_get_lines(0, 0, -1, false) -- Get all lines

    -- 1. Find the ## Todos section
    local todos_section_line_num = M.find_section_line(buffer_lines, "## Todos")

    if not todos_section_line_num then
        print("Error: '## Todos' section not found. Please create it first.")
        return
    end

    -- Determine the insertion point (1-indexed for Lua table)
    -- We'll try to find the last OPEN todo item. If none, then right after the header.
    local insertion_point_idx = todos_section_line_num + 1 -- Default to right after "## Todos" header

    local found_open_task = false
    -- Iterate through lines STARTING FROM AFTER the "## Todos" header
    for i = todos_section_line_num + 1, #buffer_lines do
        local line = buffer_lines[i]

        -- If we encounter another header, we've gone past the "## Todos" section
        if line:match("^##%s.*") then
            break
        end

        -- If it's an UNCOMPLETED task, update our potential insertion point
        if line:match("^%s*%[%s*%]%s.*") then
            insertion_point_idx = i -- This is the line of the open task
            found_open_task = true
        end
        -- We continue iterating even after finding an open task,
        -- to ensure we find the *last* open task.
    end

    -- After the loop, insertion_point_idx holds:
    -- - The line number of the *last open task* if found.
    -- - The line number of the `## Todos` header + 1 if no open tasks were found
    --   within the section, meaning it's either empty or only has completed tasks.

    -- Insert the new task line *after* the determined insertion_point_idx
    table.insert(buffer_lines, insertion_point_idx + 1, "[ ] ")

    -- 3. Update the buffer
    vim.api.nvim_buf_set_lines(0, 0, -1, false, buffer_lines)

    M.clean_up_structure() -- Call cleanup after modifications

    -- 4. Place cursor on the new line for editing
    -- The new line was inserted at `insertion_point_idx + 1`.
    -- So its 1-indexed row number is `insertion_point_idx + 1`.
    -- The column should be after "[ ] " (4 characters), so 5.
    vim.api.nvim_win_set_cursor(0, {insertion_point_idx + 1, 4}) -- Row, Col
    vim.cmd("startinsert") -- Enter Insert mode
end

-- This is crucial: return the module table so it can be required
return M
