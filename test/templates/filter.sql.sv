SELECT value FROM items WHERE 0
%for value in values:
  OR value = #{value}
