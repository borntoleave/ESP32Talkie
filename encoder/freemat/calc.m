% Talkie library
% Copyright 2011 Peter Knight
% This code is released under GPLv2 license.
%
% Main LPC mapping code.
% Converts WAV file into LPC model parameters.

clear

params = [];

% LPC10 encoder

% Read source file
% fileName = 'TomsDiner8';
%  fileName = 'pcm0808m';
 fileName = 'Untitled';
% fileName = 'force';
[a,sampleRate] = audioread(strcat(fileName,'.wav'));
fprintf('sampleRate: %d\n',sampleRate)

b=a.*0; % Output buffer, matching size

% LPC10 frame is 25ms at 8000Hz
frameTime = 0.025;

frameSamples = sampleRate * frameTime;
W = floor(2*frameSamples)  % Window is twice as long as frame, to allow for windowing overlaps

% Precalculate hanning window, length 2 frames
hannWindow = transpose(0.5*(1-cos(2*pi*(0:(W-1))/(W-1))));

% Precalculate phases for 1Hz
phase = (1:W)*2*pi/sampleRate;

lpcOrder=10;

lena = length(a);

for frameStart = 1:W/2:(lena-W)

    % Window chunk of input
    frameChunk = a(frameStart:(frameStart+W-1),1);
    frameWindowed = (frameChunk .* hannWindow);

    % Measure energy
    frameEnergy = sqrt(mean(frameWindowed.*frameWindowed));

    % Measure pitch
    pitch = 400; % Mid point of Suzanne Vega's pitch range
%     pitch = 100; % Mid point of Suzanne Vega's pitch range
%     [pitch,pitchScore] = pitchRefine(frameWindowed,pitch,1000,sampleRate);
%     [pitch,pitchScore] = pitchRefine(frameWindowed,pitch,500,sampleRate);
    [pitch,pitchScore] = pitchRefine(frameWindowed,pitch,100,sampleRate);
    [pitch,pitchScore] = pitchRefine(frameWindowed,pitch,30,sampleRate);
    [pitch,pitchScore] = pitchRefine(frameWindowed,pitch,10,sampleRate);
    [pitch,pitchScore] = pitchRefine(frameWindowed,pitch,3,sampleRate);
    % Consonant detection
    if (pitchScore/frameEnergy > 0.1)
        isVoiced = 1;
    else
        isVoiced = 0;
        pitch = 0;
    end
    
    % Calculate LPC coefficients
    r = autocorrelate(frameWindowed,lpcOrder+1);
    [k,g] = levinsonDurbin(r,lpcOrder);
    if isVoiced==0
        g = 0.1*g;
    end
    
    [frameStart/lena,g];  % Show status
    % Quantise to match bit coding
    [pitch,g,k,frameBits] = lpcQuantise(pitch,g,k);
    params = vertcat(params,frameBits);
    
    % Synthesise from parameters
    d = lpcSynth(pitch,g,k,W,lpcOrder,sampleRate);
    d = d .* hannWindow;

    % Write back pitch to output wav
    b(frameStart:floor(frameStart+2*frameSamples-1)) = b(frameStart:floor(frameStart+2*frameSamples-1)) + d;

end
b = transpose(b);
% wavwrite(b,8000,16,'TomsDinerPitch.wav');
csvwrite(strcat(fileName,'Stream.csv'),params);

%

frames = csvread(strcat(fileName,'Stream.csv'));
lastFrame = [-1,0,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1,-1]; % Jumk frame

repeatThreshold = 4;

silentFrames = 0;
repeatFrames = 0;
unvoicedFrames = 0;
voicedFrames = 0;

sizeF = size(frames);
numFrames = sizeF(1);

global bitStack; 
bitStack = "";
global fid;
fid = fopen(strcat('../../examples/Demo_Toms_Diner/',fileName,'.h'),'w');
    fprintf(fid,"const uint8_t soundData[] PROGMEM = {");

for f = 1:numFrames
    frame = frames(f,:);
    % Is this a silent frame?
    if frame(1) < 1
        % Emit a silent frame
        bitEmit(0,4);
        silentFrames = silentFrames + 1;
        lastFrame = [0,0,0,0,0,0,0,0,0,0,0,0,0];
    else
        bitEmit(frame(1),4);
        coefficientDelta = sum(abs(frame(4:13)-lastFrame(4:13)));
        if coefficientDelta <= repeatThreshold
            % Emit a repeat frame
            bitEmit(1,1);
            bitEmit(frame(3),6);
            repeatFrames = repeatFrames + 1;
            lastFrame(1) = frame(1);
            lastFrame(3) = frame(3);
        else
            bitEmit(0,1);
            bitEmit(frame(3),6);
            bitEmit(frame(4),5);
            bitEmit(frame(5),5);
            bitEmit(frame(6),4);
            bitEmit(frame(7),4);
            if frame(3) < 1
                % Emit an unvoiced frame
                unvoicedFrames = unvoicedFrames + 1;
                lastFrame = frame;
            else
                % Emit a voiced frame
                bitEmit(frame(8),4);
                bitEmit(frame(9),4);
                bitEmit(frame(10),4);
                bitEmit(frame(11),3);
                bitEmit(frame(12),3);
                bitEmit(frame(13),3);

                voicedFrames = voicedFrames + 1;
                lastFrame = frame;
            end
        end
    end
end

% Emit a stop frame
bitEmit(15,4);
fprintf(fid,"};");

fprintf('Frames:\n%d V, %d U, %d R, %d S\n',voicedFrames,unvoicedFrames,repeatFrames,silentFrames);
romSize = 50*voicedFrames + 29*unvoicedFrames + 11*repeatFrames + 4*silentFrames;
fprintf('Rom size %d bits\n',romSize);

% Output from this needs to be grouped into groups of 8 bits.
% LSB of byte is the first bit to be decoded.
% Then needs to be packaged up as a C snippet for inclusion in the libary.


