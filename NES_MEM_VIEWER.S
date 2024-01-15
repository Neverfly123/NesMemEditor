.segment "HEADER"
	.byte "NES"		;identification string
	.byte $1A
	.byte $02		;amount of PRG ROM in 16K units
	.byte $01		;amount of CHR ROM in 8K units
	.byte $01		;mapper and mirroing
	.byte $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00

.segment "ZEROPAGE"
nmi_lock:       .res 1 ; prevents NMI re-entry
nmi_count:      .res 1 ; is incremented every NMI
nmi_ready:      .res 1 ; set to 1 to push a PPU frame update, 2 to turn rendering off next NMI
PPUattribute: 	.res 1 ; STORE THE ATTRIBUTE VALUE FOR (4*4) *ALL
cursor_x:       .res 1 ; x cursor position
cursor_y:       .res 1 ; y cursor position
cursor_BgPos:	.res 2 ; cursor line position in background, used for update background character
getKey:         .res 1 ; keyinput ascii code
LastKey:		.res 1 ; Last Keyboard Input
KeyRepeat:		.res 1 ; Record howmany times same keyinput recorded
nmtUpdateCount:	.res 1 ; count howmany times nametable undated,after 8 times it go from 0 sine each time update 112byte.
PPU_nmtAdd:		.RES 2 ; PPU nametable address pointer
MemView_Start:	.res 2 ; address for mem viewer start to show
MemView_End:	.res 2 ; address for mem viewer end
BinaryVonMem:	.res 1 ; temperiory variable for convert binary value from memory to screen
Gamepad: 		.res 1
Lastgamepad: 	.res 1
PPUattributeEditor:  .res 1	;when it turn on, ppu attribute table update for mem viewer

.segment "BSS"
.org $0200
nmtBuffer: .res 896 ; nametable update entry buffer for PPU update
nmtBufferConvert: .res 128 ; nametable update entry buffer for PPU update
.reloc

.segment "STARTUP"
RESET:
	SEI 		;disables interupts
	CLD			;turn off decimal mode
	LDX #%1000000	;disable sound IRQ
	STX $4017
	LDX #$00
	STX $4010		;disable PCM
	
;initialize the stack register
	LDX #$FF
	TXS 		;transfer x to the stack
	
; Clear PPU registers
	LDX #$00
	STX $2000
	STX $2001

;WAIT FOR VBLANK
:
	BIT $2002
	BPL :-

;CLEARING 2K MEMORY
	TXA
CLEARMEMORY:
	STA $0000, X	;$0000 - $07FF
	STA $0100, X
	STA $0300, X
	STA $0400, X
	STA $0500, X
	STA $0600, X
	STA $0700, X
	sta $6000, x	;SRAM FOR PPU buffer
	sta $6100, x
	sta $6200, x
	sta $6300, x
		LDA #$FF
		STA $0200, X
		LDA #$00
	INX
	BNE CLEARMEMORY

;WAIT FOR VBLANK
:
	BIT $2002
	BPL :-
	
;SETTING SPRITE RANGE
	LDA #$02
	STA $4014
	NOP
	
;LOADPALETTES
	LDA #$3F	;$3F00
	STA $2006
	LDA #$00
	STA $2006	
	LDX #$00
	
LOADPALETTES:
	LDA PALETTEDATA, X
	STA $2007
	INX
	CPX #$20
	BNE LOADPALETTES

;LOAD BACKGROUND PALETTEDATA
	LDA #$23	;$23C0
	STA $2006
	LDA #$C0
	STA $2006
	LDX #$00
	LDA $00
	
LOADBACKGROUNDPALETTEDATA:
	STA $2007
	INX
	CPX #$40
	BNE LOADBACKGROUNDPALETTEDATA

;RESET SCROLL
	LDA #$00
	STA $2005
	STA $2005
	
;show sprites and background
	LDA #%00011110
	STA $2001

;WAIT FOR VBLANK
:
	BIT $2002
	BPL :-

;ENABLE INTERUPTS	
	LDA #%10000000
	STA $2000			;WHEN VBLANK OCCURS CALL NMI	
	CLI

Menu:
	lda #$0d
	sta getKey
	lda #$08
	sta Gamepad
	ldx #$00
	stx PPUattribute
	stx PPUattributeEditor
	jsr SetBackgroundBlack
@LOADBACKGROUND:
	LDA BACKGROUNDDATA_Menu, X
	STA nmtBuffer, x
	INX
	BNE @LOADBACKGROUND
;initialize cursor
	lda #$03
	sta cursor_y
	lda #$00
	sta cursor_x
@MainLOOP:
;determin Keyboard input
	JSR KeyInDetermin
	Bcs @Skip_KeyInput
;keyinput Display on screen
	lda getKey
	CMP #$0D		;keyboard return input
	BNE :+
	jsr MenuItemSel
	jmp Menu
	:
	cmp #$04		;keyboard up Input
	BNE :+
	lda cursor_y
	cmp #3
	beq @Skip_KeyInput
	dec cursor_y
	jmp @Skip_KeyInput
	:
	cmp #$05
	BNE @Skip_KeyInput
	lda cursor_y
	cmp #5
	beq @Skip_KeyInput
	inc cursor_y
@Skip_KeyInput:
;Determin Gamepad Input
	JSR PadInDetermin
	bcs @Skip_GamePad

	lda Gamepad
	and #PAD_START
	beq :+
		jsr MenuItemSel
		jmp Menu
	:
	lda Gamepad
	and #PAD_D
	beq :+
		lda cursor_y
		cmp #5
		beq @Skip_GamePad
		inc cursor_y
	:
	lda Gamepad
	and #PAD_U
	beq :+
		lda cursor_y
		cmp #3
		beq @Skip_GamePad
		dec cursor_y
	:
	lda Gamepad
	and #PAD_SELECT
	beq :++
		lda cursor_y
		cmp #5
		beq :+
		inc cursor_y
		jmp @Skip_GamePad
	:	
		lda #3
		sta cursor_y
		jmp @Skip_GamePad
	:
	lda Gamepad
	and #PAD_A
	beq @Skip_GamePad
		jsr MenuItemSel
		jmp Menu
@Skip_GamePad:
; ready for ppu update
	jsr ppu_update
@LoopEnd:
	JMP @MainLOOP




Viewer:
	JSR SetBackgroundBlack
;update PPU attribute
	lda #$00
	sta PPUattribute
	sta PPUattributeEditor
;initialize cursor
	lda #$04
	sta cursor_y
	lda #$00
	sta cursor_x
	ldx #$00
@LOADBACKGROUND:
	LDA BACKGROUNDDATA_Viwer, X
	STA nmtBuffer, x
	INX
	BNE @LOADBACKGROUND
@Loop:
;determin Keyboard input
	JSR KeyInDetermin
	Bcs @Skip_KeyInput
;keyinput Display on screen
	lda getKey
	and #%01100000	;see if it is printable characters
	beq :+
	JSR CursorInBackground
	ldy cursor_x
	lda getKey
	sta (cursor_BgPos),Y
	jsr CursorShift_Hex
	jmp @Skip_KeyInput
	:
	lda getKey
	CMP #$0D		;keyboard return input
	BNE :+
	lda cursor_y
	cmp #6			;check see if cursor at last input line
	beq @StartHexViewer
	JSR KbReturn_hex
	jmp @Skip_KeyInput
@StartHexViewer:
	jsr HexViewerCode
	jmp Viewer
	:
	cmp #$08		;keyboard del Input
	BNE :+
	jsr KbDel_Hex
	:
	cmp #$1B	;ESC
	BNE @Skip_KeyInput
	rts
@Skip_KeyInput:
;Determin Gamepad Input
	JSR PadInDetermin
	bcs @Skip_GamePad
	
	lda Gamepad
	and #PAD_B
	beq :+
		rts
	:
	lda Gamepad
	and #PAD_A
	beq :+
		jsr push_a
		bcc @Skip_GamePad
		jmp Viewer
	:
	lda Gamepad
	and #PAD_U
	beq :+
		jsr push_u
	:
	lda Gamepad
	and #PAD_D
	beq :+
		jsr push_d
	:
	lda Gamepad
	and #PAD_L
	beq :+
		jsr push_l
	:
	lda Gamepad
	and #PAD_R
	beq :+
		jsr push_r
	:
	lda Gamepad
	and #PAD_SELECT
	beq :+
		jsr push_select
	:
	lda Gamepad
	and #PAD_START
	beq @Skip_GamePad
		jsr push_a
		bcc @Skip_GamePad
		jmp Viewer
@Skip_GamePad:
; ready for ppu update
	jsr ppu_update
	Jmp @Loop
@ViewerLoopEnd:
	rts




Editor:
	JSR SetBackgroundBlack
;update PPU attribute
	lda #$EE
	sta PPUattribute
	sta PPUattributeEditor
;initialize cursor
	lda #$06
	sta cursor_y
	lda #$00
	sta cursor_x
	ldx #$00
@LOADBACKGROUND:
	LDA BACKGROUNDDATA_Editor, X
	STA nmtBuffer, x
	INX
	BNE @LOADBACKGROUND
@Loop:
;determin Keyboard input
	JSR KeyInDetermin
	Bcs @Skip_KeyInput
	lda getKey
	and #%01100000	;see if it is printable characters
	beq :+
	JSR CursorInBackground
	ldy cursor_x
	lda getKey
	sta (cursor_BgPos),Y
	jsr CursorShift_Editor
	jmp @Skip_KeyInput
	:
	lda getKey
	cmp # $04	;up
	bne :+
	jsr CursorShiftU_Editor
	jmp @Skip_KeyInput
	:
	cmp # $05	;down
	bne :+
	jsr CursorShiftD_Editor
	jmp @Skip_KeyInput
	:
	cmp # $0e	;left
	bne :+
	jsr CursorShiftL_Editor
	jmp @Skip_KeyInput
	:
	cmp # $0f	;right
	bne :+
	jsr CursorShift_Editor
	jmp @Skip_KeyInput
	:
	CMP #$0D	;keyboard return input
	BNE :+
	jsr KbReturn_Editor		;check see if cursor at edit area
	bcs @EditorLoopEnd
	jmp @Skip_KeyInput
	:
	cmp #$1B	;ESC
	BNE @Skip_KeyInput
	rts
@Skip_KeyInput:
;Determin Gamepad Input
	JSR PadInDetermin
	bcs @Skip_GamePad
	
	lda Gamepad
	and #PAD_START
	beq :+
		jsr KbReturn_Editor		;check see if cursor at edit area
		bcs @EditorLoopEnd
		jmp @Skip_GamePad
	:
	lda Gamepad
	and #PAD_U
	beq :++
		lda cursor_y
		cmp #6
		bne :+
		jsr push_u
	:
		jsr CursorShiftU_Editor
	:
	lda Gamepad
	and #PAD_D
	beq :++
		lda cursor_y
		cmp #6
		bne :+
		jsr push_d
	:
		jsr CursorShiftD_Editor
	:
	lda Gamepad
	and #PAD_L
	beq :+
		jsr CursorShiftL_Editor
	:
	lda Gamepad
	and #PAD_R
	beq :+
		jsr CursorShift_Editor
	:
	lda Gamepad
	and #PAD_SELECT
	beq :+
		rts
	:
	lda Gamepad
	and #PAD_B
	beq :+
		jsr push_d
	:
	lda Gamepad
	and #PAD_A
	beq @Skip_GamePad
		jsr push_u
@Skip_GamePad:
; ready for ppu update
	jsr ppu_update
	Jmp @Loop
@EditorLoopEnd:
	rts




PC:
;update PPU attribute
	ldx #$00
	stx PPUattribute
	stx PPUattributeEditor
	jsr SetBackgroundBlack
;initialize cursor
	lda #$04
	sta cursor_y
	lda #$00
	sta cursor_x
	ldx #$00
@LOADBACKGROUND:
	LDA BACKGROUNDDATA_PC, X
	STA nmtBuffer+96, x
	INX
	CPX #9
	BNE @LOADBACKGROUND
@Loop:
; ready for ppu update
;determin Keyboard input
	JSR KeyInDetermin
	Bcs @Skip_KeyInput
;keyinput Display on screen
	lda getKey
	and #%01100000	;see if it is printable characters
	beq :++
	ldy cursor_x
	lda getKey
	sta nmtBuffer,Y
	cpy #3
	beq :+
	inc cursor_x
	:
	lda #0
	sta cursor_x
	jmp @Skip_KeyInput
	:
	lda getKey
	CMP #$0D		;keyboard return input
	BNE :+
	jsr SetPC
	jmp RESET		;check see if cursor at last input line
	:
	cmp #$1B	;ESC
	BNE @Skip_KeyInput
	rts
@Skip_KeyInput:
;Determin Gamepad Input
	JSR PadInDetermin
	bcs @Skip_GamePad
	
	lda Gamepad
	and #PAD_B
	beq :+
		rts
	:
	lda Gamepad
	and #PAD_A
	beq :+
		jsr SetPC
		jmp RESET
	:
	lda Gamepad
	and #PAD_U
	beq :+
		jsr push_u
	:
	lda Gamepad
	and #PAD_D
	beq :+
		jsr push_d
	:
	lda Gamepad
	and #PAD_R
	beq :+
		ldx cursor_x
		cpx #3
		beq :+
		inc cursor_x
	:
	lda Gamepad
	and #PAD_L
	beq :+
		ldx cursor_x
		cpx #0
		beq :+
		dec cursor_x
	:
	lda Gamepad
	and #PAD_SELECT
	beq :+
		rts
	:
	lda Gamepad
	and #PAD_START
	beq @Skip_GamePad
		jsr SetPC
		jmp PC
@Skip_GamePad:
	jsr ppu_update
	Jmp @Loop
@PCLoopEnd:
	rts

;FOLLOWING CODE ARE SUB RUTINES------------------------------------------------------
	;Control Pad
	PAD_A      = $01
	PAD_B      = $02
	PAD_SELECT = $04
	PAD_START  = $08
	PAD_U      = $10
	PAD_D      = $20
	PAD_L      = $40
	PAD_R      = $80

	; gamepad_poll: this reads the Gamepad state into the variable labelled "Gamepad"
	;   This only reads the first Gamepad, and also if DPCM samples are played they can
	;   conflict with Gamepad reading, which may give incorrect results.
	gamepad_poll:
		lda Gamepad
		sta Lastgamepad
		; strobe the Gamepad to latch current button state
		lda #1
		sta $4016
		lda #0
		sta $4016
		; read 8 bytes from the interface at $4016
		ldx #8
		:
			pha
			lda $4016
			; combine low two bits and store in carry bit
			and #%00000011
			cmp #%00000001
			pla
			; rotate carry into Gamepad variable
			ror
			dex
			bne :-
		sta Gamepad
		rts

	push_u:
		jsr CursorInBackground
		ldy cursor_x
		lda (cursor_BgPos), Y
		tax
		INX
		TXA
		and #%00001111
		ora #%01100000
		sta (cursor_BgPos), Y
		rts
	push_d:
		jsr CursorInBackground
		ldy cursor_x
		lda (cursor_BgPos), Y
		tax
		deX
		TXA
		and #%00001111
		ora #%01100000
		sta (cursor_BgPos), Y
		rts	
	push_l:
		jmp CursorShiftL_Hex
	push_r:
		jmp CursorShift_Hex
	push_a:
		lda cursor_y
		cmp #6			;check see if cursor at last input line
		BNE :+
		jsr HexViewerCode
		sec
		rts
		:
		jsr KbReturn_hex
		CLC
		rts
	push_b:	
		JSR CursorInBackground
		ldy cursor_x
		lda #0
		sta (cursor_BgPos), Y
		rts
	push_select:
		lda cursor_y
		cmp #4
		beq :+
		lda #4
		sta cursor_y
		rts
		:
		lda #6
		sta cursor_y
		rts
		
	; ScanKeyboard
	ScanKey:
		lda getKey
		sta LastKey
		ldx #$00
		lda #$05
		sta $4016	;reset to row 0, column 0
	@LoopCol:
		lda #$04
		sta $4016	;select column 0, next row if not just reset
		lda $4017
		EOR #$FF
		AND #%00011110
		bne @ColumnDecode
		INX
	;LoopCol1:
		lda #$06
		sta $4016	;select column 1, next row if not just reset
		lda $4017
		EOR #$FF
		AND #%00011110
		bne @ColumnDecode
		INX
		cpx #$12
		bne @LoopCol
		lda #$00
		sta getKey
		jmp @ScanKeyEnd
	@ColumnDecode:
		lsr A
		lsr A
		cmp #$4
		BNE :+
		lda #$3		;CONVERT COLUMN BIT INTO COLUMN NUMBER TO MATCH THE KeyboardMartix
		:
		sta getKey
		txa
		asl
		asl			;CONVERT ROW NUMBER INTO THE 3RD BIT OF KeyboardMartix
		ora getKey	;NOW INPUT BIT CAN MATCH THE KeyboardMartixs address
		tax
		lda KeyboardMartix_Hex, x	;this is for hex mode
		sta getKey
	@ScanKeyEnd:
		rts
		
	KeyInDetermin:		;Determin whether should get input from keboard, clear carry if input are allowed
		jsr	ScanKey
		beq @Skip_KeyInput
		LDX LastKey
		BEQ :+
		cmp LastKey
		BNE :+
		ldx KeyRepeat
		cpx #30
		beq @RepeatKeyBoardIn
		inx
		stx KeyRepeat
		jmp @Skip_KeyInput
	@RepeatKeyBoardIn:
		lda nmi_count
		and #%0000111	;repeat same key input every 16 vblank cycle if a key is pressed
		beq :++	
		jmp @Skip_KeyInput
		:
		ldx #0
		stx KeyRepeat
		:
		clc
		rts
	@Skip_KeyInput:
		sec
		rts	
	
	PadInDetermin:		;Determin whether should get input from Gamepad, clear carry if input are allowed
		jsr gamepad_poll
		cmp #0
		beq @Skip_GamePad
		LDX Lastgamepad
		cpx #0
		BEQ :+
		cmp Lastgamepad
		BNE :+
		ldx KeyRepeat
		cpx #30
		beq @RepeatKeyPadIn
		inx
		stx KeyRepeat
		jmp @Skip_GamePad
	@RepeatKeyPadIn:
		lda nmi_count
		and #%0000111	;repeat same key input every 16 vblank cycle if a key is pressed
		beq :++	
		jmp @Skip_GamePad
		:
		ldx #0
		stx KeyRepeat
		; respond to Gamepad state
		:
		clc
		rts
	@Skip_GamePad:
		sec
		rts
	
	MenuItemSel:
		lda cursor_y
		cmp #3
		bne :+
		jsr Viewer
		rts
	:	
		CMP #4
		bne :+
		jsr Editor
		rts
	:
		CMP #5
		bne :+
		jsr PC
		rts

	CursorInBackground:		;get current cursor line address in background
		LDA #0
		STA cursor_BgPos+1
		lda cursor_y
		CLC
		asl
		rol cursor_BgPos+1
		asl 
		rol cursor_BgPos+1
		asl
		rol cursor_BgPos+1
		asl
		rol cursor_BgPos+1
		asl
		rol cursor_BgPos+1
		sta cursor_BgPos
		lda #<nmtBuffer
		adc cursor_BgPos
		sta cursor_BgPos
		lda #>nmtBuffer
		adc cursor_BgPos+1
		sta cursor_BgPos+1
		rts

	CursorShift:
		ldy cursor_x
		CPY #31
		BNE :+
		jsr KbReturn
		JMP @EndCursorShift
		:
		inc cursor_x
	@EndCursorShift:
		rts
	
	CursorShift_Hex:
		ldy cursor_x
		CPY #3
		BNE :+
		jsr KbReturn_hex
		JMP @EndCursorShiftHex
		:
		inc cursor_x
	@EndCursorShiftHex:
		rts
	
	CursorShift_Editor:
		ldy cursor_y
		cpy #6
		BNE :++
			ldx cursor_x
			bne :+
			inc cursor_x
			rts
		:
			dec cursor_x
			rts
		:
		ldx cursor_x
		cpx #31
		beq :+
			inc cursor_x
			rts
		:			;cursor at the end of the line
		lda #0
		sta cursor_x
		cpy #22
		beq :+
			inc cursor_y
			rts
		:
		lda #7			;when cursor shift to the end of 256 byte roll back the starting position
		sta cursor_y
		rts

	CursorShiftL_Editor:
		ldy cursor_y
		cpy #6
		BNE :++
			ldx cursor_x
			bne :+
			inc cursor_x
			rts
		:
			dec cursor_x
			rts
		:
		ldx cursor_x
		beq :+
			dec cursor_x
			rts
		:
		lda #31
		sta cursor_x
		cpy #7
		beq :+
			dec cursor_y
			rts
		:
		lda #22
		sta cursor_y
		rts
	
	CursorShiftU_Editor:
		ldy cursor_y
		cpy #6
		beq @CursorShiftU_EditorEnd
		cpy #7
		beq :+
		dec cursor_y
		rts
		:
		ldy #22
		sty cursor_y
	@CursorShiftU_EditorEnd:
		rts
	
	CursorShiftD_Editor:
		ldy cursor_y
		cpy #6
		beq @CursorShiftD_EditorEnd
		cpy #22
		beq :+
		inc cursor_y
		rts
		:
		ldy #7
		sty cursor_y
	@CursorShiftD_EditorEnd:
		rts
	
	CursorShiftL:		;shift cursor to left
		ldx cursor_x
		BNE :+
		ldy cursor_y
		Beq @EndCursorShiftL
		lda #31
		sta cursor_x
		dec cursor_y
		JMP @EndCursorShiftL
		:
		dec cursor_x
	@EndCursorShiftL:
		rts

	CursorShiftL_Hex:		;shift cursor to left for memory viewer
		ldx cursor_x
		CPx #0
		BNE :+
		lda #3
		sta cursor_x
		lda #4
		sta cursor_y
		JMP @EndCursorShiftLHex
		:
		dec cursor_x
	@EndCursorShiftLHex:
		rts

	KbReturn:			;once cursor move to the bottom of screen then loop back to the topleft.
		LDy #0
		STy cursor_x
		inc cursor_y
		lda cursor_y
		cmp #28
		bne @KbReturnEnd
		sty cursor_y
	@KbReturnEnd:
		rts
		
	KbReturn_hex:
		LDA #0
		STA cursor_x
		lda #6
		sta cursor_y
	@KbReturnHexEnd:
		rts
		
	KbReturn_Editor:
		ldy cursor_y
		cpy #6
		BNE :+
		inc cursor_y
		ldx #0
		stx cursor_x
		jsr ShowFFbytes
		CLC		;sec carry to mark memory update not carry on
		rts
		:
		jsr EditTheMem
		sec 	;set carry to mark this Memory update complete
		rts
	
	ShowFFbytes:
		jsr StartingMemCal_Editor
		ldy #$00
		ldx #$00
		:
		TXA
		pha
		asl
		tax
		lda (MemView_Start), y
		pha
		jsr BIN_HEX_HighBIT
		sta nmtBuffer+224, x
		pla
		jsr BIN_HEX_LowBIT
		sta nmtBuffer+225, x
		pla
		tax
		iny
		INX
		CPY #128
		BNE :-
		;second half of 256 byte
		ldy #0
		ldx #0
		lda #128
		sta MemView_Start
		:
		txa
		pha
		asl
		tax
		lda (MemView_Start), y
		pha
		jsr BIN_HEX_HighBIT
		sta nmtBuffer+480, x
		pla
		jsr BIN_HEX_LowBIT
		sta nmtBuffer+481, x
		pla
		tax
		iny
		INX
		CPY #128	
		bne :-
		lda #0
		sta MemView_Start
		rts
		
	StartingMemCal_Editor:	
	;calculate low byte of start address
		lda #$00	;low byte of starting address are always 0
		sta MemView_Start	
	;calculate high byte of start address
		lda nmtBuffer+193	;low bit of high byte start address
		and #%00001111
		sta MemView_Start+1
		lda nmtBuffer+192	;high bit of high byte start address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_Start+1
		sta MemView_Start+1
		rts	
	
	EditTheMem:
		jsr StartingMemCal_Editor
		ldy #$00
	:	;store first 128 byte to memory
		Tya
		asl
		tax
		lda nmtBuffer+224, x
		and #%00001111
		asl
		asl
		asl
		asl
		sta MemView_End
		lda nmtBuffer+225, x	;convert data in ppu Buffer table to hex value
		and #%00001111
		ora MemView_End
		sta (MemView_Start), y	;STOR THE DATA TO ASSIGNED MEMORY
		iny
		cpy #128
		bne :-
		;calculate the designated address of 2nd 128 byte memory
		tya
		CLC
		adc MemView_Start
		sta MemView_Start
		lda #0
		adc MemView_Start+1
		sta MemView_Start+1
		ldy #$00
	:	;store second 128 byte to memory
		Tya
		asl
		tax
		lda nmtBuffer+480, x
		and #%00001111
		asl
		asl
		asl
		asl
		sta MemView_End
		lda nmtBuffer+481, x	;convert data in ppu Buffer table to hex value
		and #%00001111
		ora MemView_End
		sta (MemView_Start), y	;STOR THE DATA TO ASSIGNED MEMORY
		iny
		cpy #128
		bne :-
		jsr SetBackgroundBlack
		@LOADBACKGROUND:
		LDA BACKGROUNDDATA_SUCCEED, X
		STA nmtBuffer, x
		INX
		CPX #29
		BNE @LOADBACKGROUND
		JSR KeyInToContinueEditor
		rts
		
	KbDel:
		jsr CursorShiftL
		JSR CursorInBackground
		ldy cursor_x
		lda #0
		sta (cursor_BgPos), Y
	@KbDelEnd:
		rts

	KbDel_Hex:		;for memory viewer
		jsr CursorShiftL_Hex
		JSR CursorInBackground
		ldy cursor_x
		lda #0
		sta (cursor_BgPos), Y
	@KbDelHexEnd:
		rts

	StartingAddCal:
	;calculate low byte of start address
		lda nmtBuffer+131	;low bit of low byte start address
		and #%00001111
		sta MemView_Start
		lda nmtBuffer+130	;high bit of low byte start address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_Start
		sta MemView_Start	
	;calculate high byte of start address
		lda nmtBuffer+129	;low bit of high byte start address
		and #%00001111
		sta MemView_Start+1
		lda nmtBuffer+128	;high bit of high byte start address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_Start+1
		sta MemView_Start+1
		rts

	HexViewerCode:
		jsr StartingAddCal
	;calculate low byte of end address
		lda nmtBuffer+195	;low bit of low byte end address
		and #%00001111
		sta MemView_End
		lda nmtBuffer+194	;high bit of low byte end address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_End
		sta MemView_End
	;calculate byte bit of end address
		lda nmtBuffer+193	;low bit of high byte end address
		and #%00001111
		sta MemView_End+1
		lda nmtBuffer+192	;high bit of high byte end address
		and #%00001111
		asl
		asl
		asl
		asl
		ora MemView_End+1
		sta MemView_End+1
		sec
		lda MemView_End
		sbc MemView_Start
		LDA MemView_End+1
		sbc MemView_Start+1
		BCS :+
		jsr SetBackgroundBlack
		jmp @HexViewerEnd	;IF START ADDRESS GREATER THAN END ADDRESS, RESET PROGRAM
		:
		jsr SetBackgroundBlack
	;SET ATTTIBUTE TABLE VALUE	
		lda #$EE
		sta PPUattribute
	;SET CURSOR POSITION AT TOP LEFT OF THE SCREEN
		LDA #0
		STA cursor_x
		LDA #0
		STA cursor_y
		
	;DISPLAY MEMORY ADDRESS ON SCREEN	
	@NewSubPage:
		JSR CursorInBackground
		;DISPLAY high byte
		LDY #0
		LDA MemView_Start+1 
		JSR BIN_HEX_HighBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INY
		LDA MemView_Start+1 
		JSR BIN_HEX_LowBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INY
		;DISPLAY low byte
		LDA MemView_Start
		jsr BIN_HEX_HighBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INY
		LDA MemView_Start
		JSR BIN_HEX_LowBIT
		STA (cursor_BgPos), Y	;STORE THE HEXDEC CODE TO PPU buffer
		INC cursor_y
		;DISPLAY a line of 16 BYTEs IN SELECTED MEMORY sub PAGE
		JSR CursorInBackground
		LDX MemView_Start
		LDY #0
		:
		LDA (MemView_Start), Y
		sta BinaryVonMem
		tya
		pha
		ASL
		tay
		lda BinaryVonMem
		JSR BIN_HEX_HighBIT
		STA (cursor_BgPos), Y
		iny
		lda BinaryVonMem
		jsr BIN_HEX_LowBIT
		STA (cursor_BgPos), Y
		pla
		tay
		INY
		INX
		TXA		;check for PPU update every 2 lines Input
		and #%00001111
		BNE :-
		;check if reach the end of the inputed memory address
		inc cursor_y
		lda cursor_y
		cmp #28
		BNE @Skip_KeyInput
		lda #0
		sta cursor_y
		jsr KeyInToContinue
		BCC :+
		rts
		:
		jsr SetBackgroundBlack
		@Skip_KeyInput:
		LDA MemView_Start		;if reachs 16 byte means current line is full, new line needed
		and #%11110000
		CLC
		adc #$10				;add #16 to get memory address showing at next line 
		sta MemView_Start
		lda #0
		adc MemView_Start+1
		sta MemView_Start+1
		;Check for end
		sec
		lda MemView_End
		sbc MemView_Start
		LDA MemView_End+1
		sbc MemView_Start+1
		BCC @HexViewerEnd
		jmp @NewSubPage
	@HexViewerEnd:
		jsr KeyInToContinue
		rts
		
	SetPC:
		jsr StartingAddCal
		jmp (MemView_Start)
		
	KeyInToContinue:		;wait enter key to turn screen to next page
		jsr ppu_update
		jsr gamepad_poll
		jsr	ScanKey
		ora Gamepad
		beq KeyInToContinue
		LDa LastKey
		ora Lastgamepad
		BEQ :+
		lda getKey
		cmp LastKey
		beq KeyInToContinue
		lda Gamepad
		cmp Lastgamepad
		beq KeyInToContinue
		:
		lda getKey
		CMP #$0D			;keyboard return input
		beq @EndWait
		CMP #$1B
		beq @EndProgram
		lda Gamepad
		CMP #PAD_D
		beq @EndWait
		CMP #PAD_START
		beq @EndProgram
		Jmp KeyInToContinue
	@EndWait:
		CLC
		rts
	@EndProgram:
		sec			;set carrt to mark end viewing page
		rts
	
	KeyInToContinueEditor:		;wait enter key to turn screen to next page
		jsr ppu_update
		jsr gamepad_poll
		jsr	ScanKey
		ora Gamepad
		beq KeyInToContinue
		LDa LastKey
		ora Lastgamepad
		BEQ :+
		lda getKey
		cmp LastKey
		beq KeyInToContinue
		lda Gamepad
		cmp Lastgamepad
		beq KeyInToContinue
		:
		lda getKey
		CMP #$0D			;keyboard return input
		beq @EndProgram
		lda Gamepad
		CMP #PAD_START
		beq @EndProgram
		Jmp KeyInToContinue
	@EndProgram:
		rts
	
	BIN_HEX_HighBIT:		;convert hexdecimal to readable character
		AND #%11110000
		lsr
		lsr
		lsr
		lsr
		ORA #%01100000		;FORM THE CODE CAN MATCH THE KeyboardMartix_Hex FOR THE LEFT 4 BIT BINARY
		rts
		
	BIN_HEX_LowBIT:			;convert hexdecimal to readable character
		AND #%00001111
		ORA #%01100000		;FORM THE CODE CAN MATCH THE KeyboardMartix_Hex FOR THE right 4 BIT BINARY
		rts
	
	SetBackgroundBlack:
		ldx #0
		txa
	@LOADBACKGROUND:
		STA nmtBuffer, x
		STA nmtBuffer+256, x
		STA nmtBuffer+512, x
		inx
		BNE @LOADBACKGROUND
		ldx #$80
	@LOADBACKGROUNDP4:
		dex
		STA nmtBuffer+768, x
		BNE @LOADBACKGROUNDP4
		rts

	ppu_update:	
		JSR TableConvert
		lda #1
		sta nmi_ready
		:
			lda nmi_ready
			bne :-
		rts

	TableConvert:	;convert for v-blank input, in order to minimize the table scan cycle
		ldx #0
		ldy #128
		lda nmtUpdateCount
		cmp #6
		bne @Table1
		:
		lda nmtBuffer, x
		sta nmtBufferConvert-1, y
		inx
		dey
		bne :-
		lda #$20
		sta PPU_nmtAdd+1
		sta PPU_nmtAdd
		jmp @DECnmtUpdateCount
	@Table1:
		cmp #5
		bne @Table2
		:
		lda nmtBuffer+128, x
		sta nmtBufferConvert-1, y
		inx
		dey
		bne :-
		lda #$20
		sta PPU_nmtAdd+1
		LDA #$a0
		sta PPU_nmtAdd
		jmp @DECnmtUpdateCount
	@Table2:
		cmp #4
		bne @Table3
		:
		lda nmtBuffer+256, x
		sta nmtBufferConvert-1, y
		inx
		dey
		bne :-
		lda #$21
		sta PPU_nmtAdd+1
		LDA #$20
		sta PPU_nmtAdd
		jmp @DECnmtUpdateCount
	@Table3:	
		cmp #3
		bne @Table4
		:
		lda nmtBuffer+384, x
		sta nmtBufferConvert-1, y
		inx
		dey
		bne :-
		lda #$21
		sta PPU_nmtAdd+1
		LDA #$a0
		sta PPU_nmtAdd
		jmp @DECnmtUpdateCount
	@Table4:
		cmp #2
		bne @Table5
		:
		lda nmtBuffer+512, x
		sta nmtBufferConvert-1, y
		inx
		dey
		bne :-
		lda #$22
		sta PPU_nmtAdd+1
		LDA #$20
		sta PPU_nmtAdd
		jmp @DECnmtUpdateCount
	@Table5:
		cmp #1
		bne @Table6
		:
		lda nmtBuffer+640, x
		sta nmtBufferConvert-1, y
		inx
		dey
		bne :-
		lda #$22
		sta PPU_nmtAdd+1
		LDA #$a0
		sta PPU_nmtAdd
		jmp @DECnmtUpdateCount
	@Table6:
		lda nmtBuffer+768, x
		sta nmtBufferConvert-1, y
		inx
		dey
		bne @Table6
		lda #$23
		sta PPU_nmtAdd+1
		LDA #$20
		sta PPU_nmtAdd
		LDA #6
		STA nmtUpdateCount
		jmp @EndTableConvert
	@DECnmtUpdateCount:
		DEC nmtUpdateCount
	@EndTableConvert:
		rts
;--------------------------	v-blank ----------------------------------------------------------	
NMI:
; save registers
	pha
	txa
	pha
	tya
	pha
; prevent NMI re-entry
	lda nmi_lock
	beq :+
		jmp @nmi_end
	:
	lda #1
	sta nmi_lock
; increment frame counter
	inc nmi_count
; decide whether enter ppu undate or not
	lda nmi_ready
	bne :+ ; nmi_ready == 0 not ready to update PPU
		jmp @ppu_update_end
	:
;Calculate whether cursor should display or hide
	LDA #$00		;hold the address in SPR-RAM to access on the bext write to $2004
	STA $2003
	lda nmi_count
	and #%00100000	;cursor blink every 64 v-blank
	beq :+
		lda #$FF
		jmp @REFRESHCURSOR
	:
	lda cursor_y
	CLC
	adc #1
	asl
	asl
	asl
@REFRESHCURSOR:
	STA $2004	;Y
	LDA #$FF
	STA $2004	;CURSOR character ADDRESS
	LDA #$00
	STA $2004	;attributes
	LDA cursor_x
	clc
	asl
	asl
	asl
	STA $2004	;X	
;Update Background
	LDA $2002		;read PPU status to reset high/low latch
	LDY #128
	LDA PPU_nmtAdd+1
	STA $2006
	LDA PPU_nmtAdd
	STA $2006
	:
	LDA nmtBufferConvert-1, Y
	STA $2007
	dey
	BNE :-
; set attribute table
	ldx PPUattributeEditor
	bne @UPdateForEditor
	lda #$23
	sta $2006
	lda #$C0
	sta $2006
	lda PPUattribute
	ldx #64 ; 64 bytes
	:
		sta $2007
		dex
		bne :-
	jmp @PPUattributeUpdateEnd
@UPdateForEditor:	;update attribuate table for memory editor
	lda #$23
	sta $2006
	lda #$d0
	sta $2006
	lda PPUattribute
	ldx #48 ; 48 bytes
	:
		sta $2007
		dex
		bne :-
@PPUattributeUpdateEnd:
;set PPU control register		
	LDA #%10000000
	STA $2000
	LDA #$00
	STA $2005
	STA $2005	
; enable rendering
	lda #%00011110
	sta $2001

; flag PPU update complete
	ldx #0
	stx nmi_ready
@ppu_update_end:
	; unlock re-entry flag
	lda #0
	sta nmi_lock
@nmi_end:
	; restore registers and return
	pla
	tay
	pla
	tax
	pla
	rti
;--------------------------	v-blank End----------------------------------------------------------

PALETTEDATA:
	.byte $0E, $30, $00, $10, 	$00, $0A, $15, $01, 	$00, $29, $28, $27, 	$00, $34, $24, $14 	;background palettes
	.byte $0E, $30, $15, $30, 	$00, $0F, $11, $30, 	$00, $0F, $30, $27, 	$00, $3C, $2C, $1C 	;sprite palettes

BACKGROUNDDATA_Menu:	;32*8 BYTES
	.byte $00,$00,$00,$00,$00,$00,$4e,$45,$53,$00,$4d,$45,$4d,$4f,$52,$59,$00,$45,$44,$49,$54,$4f,$52,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $50,$4c,$45,$41,$53,$45,$00,$53,$45,$4c,$45,$43,$54,$3a,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $61,$2e,$56,$49,$45,$57,$00,$4d,$45,$4d,$4f,$52,$59,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $62,$2e,$45,$44,$49,$54,$00,$4d,$45,$4d,$4f,$52,$59,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $63,$2e,$53,$45,$54,$00,$50,$52,$4f,$47,$52,$41,$4d,$00,$43,$4f,$55,$4e,$54,$45,$52,$00,$41,$4e,$44,$00,$52,$55,$4e,$00,$00,$00
	.byte $00,$00,$50,$52,$4f,$47,$52,$41,$4d,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

BACKGROUNDDATA_Viwer:	;32*8 BYTES
	.byte $4E,$45,$53,$20,$4D,$45,$4D,$4F,$52,$59,$20,$56,$49,$45,$57,$45,$52,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $49,$4E,$50,$55,$54,$20,$4D,$45,$4D,$4F,$52,$59,$20,$41,$44,$44,$52,$45,$53,$53,$20,$49,$4E,$20,$48,$45,$58,$20,$44,$45,$43,$00
	.byte $52,$41,$4E,$47,$45,$20,$42,$45,$54,$57,$45,$45,$4E,$20,$30,$30,$30,$30,$20,$2D,$20,$46,$46,$46,$46,$00,$00,$00,$00,$00,$00,$00
	.byte $53,$54,$41,$52,$54,$20,$41,$44,$44,$52,$45,$53,$53,$3A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $45,$4E,$44,$20,$41,$44,$44,$52,$45,$53,$53,$3A,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

BACKGROUNDDATA_PC:	;9 BYTES
	.byte $52,$45,$53,$45,$54,$00,$50,$43,$3A

BACKGROUNDDATA_SUCCEED:	;29 BYTEs
	.BYTE $44,$41,$54,$41,$00,$49,$4E,$50,$55,$54,$00,$54,$4F,$00,$4D,$45,$4D,$4F,$52,$59,$00,$53,$55,$43,$43,$45,$45,$44,$21

BACKGROUNDDATA_Editor:	;32*8 BYTES
	.byte $00,$00,$00,$00,$00,$00,$4E,$45,$53,$00,$4D,$45,$4D,$4F,$52,$59,$00,$45,$44,$49,$54,$4F,$52,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00	
	.byte $45,$44,$49,$54,$00,$4D,$45,$4D,$4F,$52,$59,$00,$42,$59,$00,$49,$4E,$50,$55,$54,$00,$48,$45,$58,$41,$44,$45,$43,$49,$4D,$41,$4C
	.byte $55,$50,$44,$41,$54,$45,$00,$4D,$45,$4D,$4F,$52,$59,$00,$4F,$4E,$45,$00,$50,$41,$47,$45,$00,$45,$41,$43,$48,$00,$54,$49,$4D,$45
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $49,$4E,$50,$55,$54,$00,$53,$54,$41,$52,$54,$49,$4E,$47,$00,$41,$44,$44,$52,$45,$53,$53,$3A,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$60,$60,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00
	.byte $00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00,$00

	
KeyboardMartix_Hex:
;Col   $01,$02,$03,$04 
.byte  $00,$0d,$00,$00 ;Row0,Col0
.byte  $00,$00,$66,$00 ;Row0,Col1
.byte  $00,$00,$00,$00 ;Row1,Col0
.byte  $00,$00,$00,$00 ;Row1,Col1
.byte  $00,$00,$00,$00 ;Row2,Col0
.byte  $00,$00,$00,$60 ;Row2,Col1
.byte  $00,$00,$00,$00 ;Row3,Col0
.byte  $00,$00,$69,$68 ;Row3,Col1
.byte  $00,$00,$00,$00 ;Row4,Col0
.byte  $6b,$00,$67,$66 ;Row4,Col1
.byte  $00,$00,$00,$6d ;Row5,Col0
.byte  $6f,$6c,$65,$64 ;Row5,Col1
.byte  $00,$00,$00,$6a ;Row6,Col0
.byte  $00,$00,$6e,$63 ;Row6,Col1
.byte  $00,$1B,$00,$00 ;Row7,Col0
.byte  $00,$00,$61,$62 ;Row7,Col1
.byte  $00,$04,$0f,$0e ;Row8,Col0
.byte  $05,$00,$08,$00 ;Row8,Col1
	
KeyboardMartix:
;Col   $01,$02,$03,$04 
.byte  $00,$0d,$5b,$5d ;Row0,Col0
.byte  $00,$00,$36,$18 ;Row0,Col1
.byte  $00,$40,$3a,$3b ;Row1,Col0
.byte  $5f,$2f,$2d,$5e ;Row1,Col1
.byte  $00,$4f,$4c,$4b ;Row2,Col0
.byte  $2e,$2c,$50,$30 ;Row2,Col1
.byte  $00,$49,$55,$4a ;Row3,Col0
.byte  $4d,$4e,$39,$38 ;Row3,Col1
.byte  $00,$59,$47,$48 ;Row4,Col0
.byte  $42,$56,$37,$36 ;Row4,Col1
.byte  $00,$54,$52,$44 ;Row5,Col0
.byte  $46,$43,$35,$34 ;Row5,Col1
.byte  $00,$57,$53,$41 ;Row6,Col0
.byte  $58,$5a,$45,$33 ;Row6,Col1
.byte  $00,$1B,$51,$00 ;Row7,Col0
.byte  $00,$00,$31,$32 ;Row7,Col1
.byte  $02,$04,$0f,$0e ;Row8,Col0
.byte  $05,$20,$08,$00 ;Row8,Col1

.segment "VECTORS"
	.word NMI
	.word RESET
	
.segment "CHARS"
	.incbin "character.chr"
