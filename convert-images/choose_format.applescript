on run argv
    if (count of argv) is 0 then return "CANCEL"
    set formatNames to argv
    set picked to choose from list formatNames with title "Преобразовать изображения" with prompt "Выберите формат для выделенных изображений:" default items {item 1 of formatNames} OK button name "Преобразовать" cancel button name "Отменить" without multiple selections allowed
    if picked is false then return "CANCEL"
    return item 1 of picked
end run
