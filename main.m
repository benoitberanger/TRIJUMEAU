%% Init

clear
clc

debug = 0;

%% ===>> Design <<===

restDuration   = 20; % seconds
actionDuration = 20; % seconds

nrBlocks = 10; % action ( rest = action +1 )

if debug
    restDuration   = 5; % seconds
    actionDuration = 3; % seconds
    
    nrBlocks = 2; % action ( rest = action +1 )
end



%% Check if the toolboxs are installed

assert(~isempty(which('PsychtoolboxVersion.m')),'Psychtoolbox not detected. Please install it to run the script. http://psychtoolbox.org/')
assert(~isempty(which('EventRecorder.m')),'StimTemplate not detected. Please install it to run the script. https://github.com/benoitberanger/StimTemplate.git')


%% Load audio files

SamplingRate  = 44100; % Hz

[ActionAction.signal, ActionAction.duration] = psychwavread('ActionAction.wav');
[RestRest.signal    , RestRest.duration]     = psychwavread('ReposRepos.wav'    );
ActionAction.duration = length(ActionAction.signal)/SamplingRate;
RestRest.duration     = length(RestRest.signal    )/SamplingRate;


%% Start Psychtoolbox audio engine

Playback_Mode           = 1; % 1 = playback, 2 = record
Playback_LowLatencyMode = 1; % {0,1,2,3,4}
Playback_freq           = SamplingRate ;
Playback_Channels       = 2; % 1 = mono, 2 = stereo

% Perform basic initialization of the sound driver:
InitializePsychSound(1);

% Close the audio device:
PsychPortAudio('Close')

% Playback device initialization
Playback_pahandle = PsychPortAudio('Open', [],...
    Playback_Mode,...
    Playback_LowLatencyMode,...
    Playback_freq,...
    Playback_Channels);


%% Make blocks
% blocks(i) : [0/1  duration]
% 0 => rest, 1 => action, duration in seconds

% Always start a with a rest block
blocks = [0 restDuration];

for evt = 1 : nrBlocks
    
    blocks(end+1,:) = [1 actionDuration]; %#ok<*SAGROW>
    blocks(end+1,:) = [0 restDuration  ];
    
end

fprintf('total stim duration : %d seconds \n', sum(blocks(:,2)) )


%% StimTemplate

% Create and prepare
header = { 'event_name' , 'onset(s)' , 'duration(s)'};
EP     = EventPlanning(header);

% NextOnset = PreviousOnset + PreviousDuration
NextOnset = @(EP) EP.Data{end,2} + EP.Data{end,3};

% --- Start ---------------------------------------------------------------

EP.AddPlanning({ 'StartTime' 0  0 });

% --- Stim ----------------------------------------------------------------

for evt = 1 : size(blocks,1)
    
    switch blocks(evt,1)
        case 0
            name = 'rest';
        case 1
            name = 'action';
    end
    
    EP.AddPlanning({ name NextOnset(EP) blocks(evt,2)});
    
end

% --- Stop ----------------------------------------------------------------

EP.AddPlanning({ 'StopTime' NextOnset(EP) 0 });

% Create
ER = EventRecorder( { 'event_name' , 'onset(s)' , 'durations(s)' } , size(EP.Data,1) );
% Prepare
ER.AddStartTime( 'StartTime' , 0 );


%% Keys

fprintf('\n')
fprintf('Response buttuns (fORRP 932) : \n')
fprintf('USB \n')
fprintf('don''t care about second line \n')
fprintf('HID NAR BYGRT \n')
fprintf('\n')

KbName('UnifyKeyNames');
allKeys.MRItrigger = KbName('t');
allKeys.escape     = KbName('escape');

KL = KbLogger( ...
    struct2array(allKeys) ,...
    KbName(struct2array(allKeys)));

% Start recording events
KL.Start;


%% Stimulation


for evt = 1 : size(EP.Data,1)
    
    % Command window display
    fprintf( '\n' )
    fprintf( '\n ----- %s  \n' , EP.Data{evt,1} )
    fprintf( ' Onset     = %.3g (s) \n' , EP.Data{evt,2} )
    fprintf( ' Duration  = %.3g (s) \n' , EP.Data{evt,3} )
    fprintf( ' Remaining = %.3g (s) \n' , EP.Data{end,2} - EP.Data{evt,2} )
    fprintf( '\n' )
    
    switch EP.Data{evt,1}
        
        case 'StartTime' % Waiting for MRI trigger
            
            fprintf('Waiting for MRI trigger to start the stimulation ... \n')
            
            if debug
                startTime = GetSecs;
            end
            
            while 1 && ~debug
                
                [keyIsDown, secs, keyCode] = KbCheck;
                
                if keyIsDown
                    
                    if keyCode(allKeys.MRItrigger)
                        startTime = secs;
                        fprintf('... received MRI trigger \n')
                        break
                    elseif keyCode(allKeys.escape)
                        error('ESCAPE key pressed')
                    end
                    
                end
                
            end
            
        case 'rest'
            
            PsychPortAudio('Fillbuffer', Playback_pahandle, [RestRest.signal'; RestRest.signal']);
            onset = PsychPortAudio('Start', Playback_pahandle, 1, startTime + EP.Data{evt,2} -0.001, 1);
            
            ER.AddEvent({ EP.Data{evt,1} onset-startTime [] })
            
            [keyIsDown, secs, keyCode] = KbCheck;
            while secs <  startTime +  EP.Data{evt+1,2} - ActionAction.duration - 0.005
                
                [keyIsDown, secs, keyCode] = KbCheck;
                if keyIsDown
                    if keyCode(allKeys.escape)
                        error('ESCAPE key pressed')
                    end
                end
                
            end
            
            PsychPortAudio('Fillbuffer', Playback_pahandle, [ActionAction.signal'; ActionAction.signal']);
            PsychPortAudio('Start', Playback_pahandle, 1, startTime +  EP.Data{evt+1,2} - ActionAction.duration - 0.001 , 1);
            
        case 'action'
            
            onset = WaitSecs('UntilTime', startTime+EP.Data{evt,2});
            ER.AddEvent({ EP.Data{evt,1} onset-startTime [] })
            
            [keyIsDown, secs, keyCode] = KbCheck;
            while secs <  startTime +  EP.Data{evt+1,2} - 0.005
                
                [keyIsDown, secs, keyCode] = KbCheck;
                if keyIsDown
                    if keyCode(allKeys.escape)
                        ER.AddEvent({ 'StopTime' secs-startTime [] })
                        error('ESCAPE key pressed')
                    end
                end
                
            end
            
        case 'StopTime'
            onset = WaitSecs('UntilTime', startTime+EP.Data{evt,2}+EP.Data{evt,3}  );
            ER.AddEvent({ EP.Data{evt,1} onset-startTime [] })
            
    end % switch
    
end % for

%% Stop PTB audio engine

% Close the audio device:
PsychPortAudio('Close')


%% The end

ER.ClearEmptyEvents;
ER.ComputeDurations;
ER.BuildGraph;

% KbLogger
KL.GetQueue;
KL.Stop;
KL.ScaleTime;
KL.ComputeDurations;
KL.BuildGraph;

if debug
    plotDelay(EP,ER) %#ok<*UNRCH>
end

fprintf('Stimulation done \n')
