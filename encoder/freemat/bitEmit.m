% Talkie library
% Copyright 2011 Peter Knight
% This code is released under GPLv2 license.
%
% Emit a parameter as bits

function bitEmit(val,bits)
    global bitStack;
    global fid;

    bitpos = 2^(bits-1);
    for b = 1:bits
        if bitand(val,bitpos)
%              fprintf('1');
            bitStack="1"+bitStack;
        else
%              fprintf('0');
            bitStack="0"+bitStack;
        end
        val = val*2;
    if strlength(bitStack)==8
        fprintf(fid,"0x");
        fprintf(fid,"%02X",bin2dec(bitStack));
        fprintf(fid,",");
        bitStack = "";
    end
end
    
